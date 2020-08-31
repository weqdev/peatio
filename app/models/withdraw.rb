# encoding: UTF-8
# frozen_string_literal: true

class Withdraw < ApplicationRecord
  STATES = %i[ prepared
               rejected
               accepted
               skipped
               processing
               succeed
               canceled
               failed
               errored
               confirming].freeze
  COMPLETED_STATES = %i[succeed rejected canceled failed].freeze
  SUCCEED_PROCESSING_STATES = %i[accepted skipped processing errored confirming succeed].freeze

  include AASM
  include AASM::Locking
  include BelongsToCurrency
  include BelongsToMember
  include TIDIdentifiable
  include FeeChargeable

  extend Enumerize
  TRANSFER_TYPES = { fiat: 100, crypto: 200 }

  # Optional beneficiary association gives ability to support both in-peatio
  # beneficiaries and managed by third party application.
  belongs_to :beneficiary, optional: true

  acts_as_eventable prefix: 'withdraw', on: %i[create update]

  before_validation(on: :create) { self.rid ||= beneficiary.rid if beneficiary.present? }
  before_validation { self.completed_at ||= Time.current if completed? }
  before_validation { self.transfer_type ||= coin? ? 'crypto' : 'fiat' }

  validates :rid, :aasm_state, presence: true
  validates :txid, uniqueness: { scope: :currency_id }, if: :txid?
  validates :block_number, allow_blank: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :sum,
            presence: true,
            numericality: { greater_than_or_equal_to: ->(withdraw) { withdraw.currency.min_withdraw_amount }}

  validate do
    errors.add(:beneficiary, 'not active') if beneficiary.present? && !beneficiary.active? && !aasm_state.to_sym.in?(COMPLETED_STATES)
  end

  validate :verify_limits, on: :create
  scope :completed, -> { where(aasm_state: COMPLETED_STATES) }
  scope :succeed_processing, -> { where(aasm_state: SUCCEED_PROCESSING_STATES) }
  scope :last_24_hours, -> { where('created_at > ?', 24.hour.ago) }
  scope :last_1_month, -> { where('created_at > ?', 1.month.ago) }

  aasm whiny_transitions: false do
    state :prepared, initial: true
    state :canceled
    state :accepted
    state :skipped
    state :to_reject
    state :rejected
    state :processing
    state :succeed
    state :failed
    state :errored
    state :confirming

    event :accept do
      transitions from: :prepared, to: :accepted
      after do
        lock_funds
        record_submit_operations!
      end
      after_commit do
        process! if ENV.false?('WITHDRAW_ADMIN_APPROVE') && currency.coin?
      end
    end

    event :cancel do
      transitions from: %i[prepared accepted], to: :canceled
      after do
        unless aasm.from_state == :prepared
          unlock_funds
          record_cancel_operations!
        end
      end
    end

    event :reject do
      transitions from: %i[to_reject accepted confirming], to: :rejected
      after do
        unlock_funds
        record_cancel_operations!
      end
    end

    event :process do
      transitions from: %i[accepted skipped errored], to: :processing
      after :send_coins!
    end

    event :load do
      transitions from: :accepted, to: :confirming do
        # Load event is available only for coin withdrawals.
        guard do
          coin? && txid?
        end
      end
    end

    event :dispatch do
      transitions from: :processing, to: :confirming do
        # Validate txid presence on coin withdrawal dispatch.
        guard do
          fiat? || txid?
        end
      end
    end

    event :success do
      transitions from: %i[confirming errored], to: :succeed do
        guard do
          fiat? || txid?
        end
        after do
          unlock_and_sub_funds
          record_complete_operations!
        end
      end
    end

    event :skip do
      transitions from: :processing, to: :skipped
    end

    event :fail do
      transitions from: %i[processing confirming skipped errored], to: :failed
      after do
        unlock_funds
        record_cancel_operations!
      end
    end

    event :err do
      transitions from: :processing, to: :errored, after: :add_error
    end
  end

  def account
    member&.get_account(currency)
  end

  def add_error(e)
    if error.blank?
      update!(error: [{ class: e.class.to_s, message: e.message }])
    else
      update!(error: error << { class: e.class.to_s, message: e.message })
    end
  end

  def verify_limits
    limits = WithdrawLimit.for(kyc_level: member.level, group: member.group, currency_id: currency_id)
    limit_24_hours = limits.limit_24_hour * currency.price.to_d
    limit_1_months = limits.limit_1_month * currency.price.to_d
    sum_withdraws_24_hours = member.withdraws.succeed_processing.where('created_at > ?', 24.hours.ago).sum(:sum) + sum
    sum_withdraws_1_month = member.withdraws.succeed_processing.where('created_at > ?', 1.month.ago).sum(:sum) + sum

    if sum_withdraws_24_hours > limit_24_hours
      errors.add(:withdraw, '24h_limit_exceeded')
    elsif sum_withdraws_1_month > limit_1_months
      errors.add(:withdraw, '72h_limit_exceeded')
    end
  end

  def fiat?
    Withdraws::Fiat === self
  end

  def coin?
    !fiat?
  end

  def completed?
    aasm_state.in?(COMPLETED_STATES.map(&:to_s))
  end

  def as_json_for_event_api
    { tid:             tid,
      user:            { uid: member.uid, email: member.email },
      uid:             member.uid,
      rid:             rid,
      currency:        currency_id,
      amount:          amount.to_s('F'),
      fee:             fee.to_s('F'),
      state:           aasm_state,
      created_at:      created_at.iso8601,
      updated_at:      updated_at.iso8601,
      completed_at:    completed_at&.iso8601,
      blockchain_txid: txid }
  end

private

  # @deprecated
  def lock_funds
    account.lock_funds(sum)
  end

  # @deprecated
  def unlock_funds
    account.unlock_funds(sum)
  end

  # @deprecated
  def unlock_and_sub_funds
    account.unlock_and_sub_funds(sum)
  end

  def record_submit_operations!
    transaction do
      # Debit main fiat/crypto Liability account.
      # Credit locked fiat/crypto Liability account.
      Operations::Liability.transfer!(
        amount:     sum,
        currency:   currency,
        reference:  self,
        from_kind:  :main,
        to_kind:    :locked,
        member_id:  member_id
      )
    end
  end

  def record_cancel_operations!
    transaction do
      # Debit locked fiat/crypto Liability account.
      # Credit main fiat/crypto Liability account.
      Operations::Liability.transfer!(
        amount:     sum,
        currency:   currency,
        reference:  self,
        from_kind:  :locked,
        to_kind:    :main,
        member_id:  member_id
      )
    end
  end

  def record_complete_operations!
    transaction do
      # Debit locked fiat/crypto Liability account.
      Operations::Liability.debit!(
        amount:     sum,
        currency:   currency,
        reference:  self,
        kind:       :locked,
        member_id:  member_id
      )

      # Credit main fiat/crypto Revenue account.
      # NOTE: Credit amount = fee.
      Operations::Revenue.credit!(
        amount:     fee,
        currency:   currency,
        reference:  self,
        member_id:  member_id
      )

      # Debit main fiat/crypto Asset account.
      # NOTE: Debit amount = sum - fee.
      Operations::Asset.debit!(
        amount:     amount,
        currency:   currency,
        reference:  self
      )
    end
  end

  def send_coins!
    AMQP::Queue.enqueue(:withdraw_coin, id: id) if coin?
  end
end

# == Schema Information
# Schema version: 20200827105929
#
# Table name: withdraws
#
#  id             :integer          not null, primary key
#  member_id      :integer          not null
#  beneficiary_id :bigint
#  currency_id    :string(10)       not null
#  amount         :decimal(32, 16)  not null
#  fee            :decimal(32, 16)  not null
#  txid           :string(128)
#  aasm_state     :string(30)       not null
#  block_number   :integer
#  sum            :decimal(32, 16)  not null
#  type           :string(30)       not null
#  transfer_type  :integer
#  tid            :string(64)       not null
#  rid            :string(256)      not null
#  note           :string(256)
#  error          :json
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  completed_at   :datetime
#
# Indexes
#
#  index_withdraws_on_aasm_state            (aasm_state)
#  index_withdraws_on_currency_id           (currency_id)
#  index_withdraws_on_currency_id_and_txid  (currency_id,txid) UNIQUE
#  index_withdraws_on_member_id             (member_id)
#  index_withdraws_on_tid                   (tid)
#  index_withdraws_on_type                  (type)
#
