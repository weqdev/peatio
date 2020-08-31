# encoding: UTF-8
# frozen_string_literal: true

module API
  module V2
    module Admin
      class Wallets < Grape::API
        helpers ::API::V2::Admin::Helpers
        helpers do
          # Collection of shared params, used to
          # generate required/optional Grape params.
          OPTIONAL_WALLET_PARAMS ||= {
            settings: {
              type: { value: JSON, message: 'admin.wallet.non_json_settings' },
              default: {},
              desc: -> { 'Wallet settings' }
            },
            max_balance: {
              type: { value: BigDecimal, message: 'admin.blockchain.non_decimal_max_balance' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.wallet.invalid_max_balance' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Wallet.documentation[:max_balance][:desc] }
            },
            status: {
              values: { value: %w(active disabled), message: 'admin.wallet.invalid_status' },
              default: 'active',
              desc: -> { API::V2::Admin::Entities::Wallet.documentation[:status][:desc] }
            },
          }

          params :create_wallet_params do
            OPTIONAL_WALLET_PARAMS.each do |key, params|
              optional key, params
            end
          end

          params :update_wallet_params do
            OPTIONAL_WALLET_PARAMS.each do |key, params|
              optional key, params.except(:default)
            end
          end
        end

        desc 'Get all wallets, result is paginated.',
          is_array: true,
          success: API::V2::Admin::Entities::Wallet
        params do
          optional :blockchain_key,
                   values: { value: -> { ::Blockchain.pluck(:key) }, message: 'admin.currency.blockchain_key_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:blockchain_key][:desc] }
          optional :kind,
                   values: { value: -> { Wallet.kind.values }, message: 'admin.wallet.invalid_kind' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:kind][:desc] }
          optional :currencies,
                   values: { value: ->(v) { Array.wrap(v).all? { |value| value.in? ::Currency.codes } }, message: 'admin.wallet.currency_doesnt_exist' },
                   types: [String, Array], coerce_with: ->(c) { [*c] },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
          use :pagination
          use :ordering
        end
        get '/wallets' do
          admin_authorize! :read, Wallet

          ransack_params = Helpers::RansackBuilder.new(params)
                             .eq(:blockchain_key)
                             .translate_in(currencies: :currencies_id)
                             .merge(kind_eq: params[:kind].present? ? Wallet.kinds[params[:kind].to_sym] : nil)
                             .build

          search = ::Wallet.joins(:currencies).ransack(ransack_params)
          search.sorts = "#{params[:order_by]} #{params[:ordering]}"
          present paginate(search.result), with: API::V2::Admin::Entities::Wallet
        end

        desc 'List wallet kinds.'
        get '/wallets/kinds' do
          ::Wallet.kind.values
        end

        desc 'List wallet gateways.'
        get '/wallets/gateways' do
          ::Wallet.gateways.map(&:to_s)
        end

        desc 'Get a wallet.' do
          success API::V2::Admin::Entities::Wallet
        end
        params do
          requires :id,
                   type: { value: Integer, message: 'admin.wallet.non_integer_id' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:id][:desc] }
        end
        get '/wallets/:id' do
          admin_authorize! :read, Wallet

          present ::Wallet.find(params[:id]), with: API::V2::Admin::Entities::Wallet
        end

        desc 'Creates new wallet.' do
          success API::V2::Admin::Entities::Wallet
        end
        params do
          use :create_wallet_params
          requires :blockchain_key,
                   values: { value: -> { ::Blockchain.pluck(:key) }, message: 'admin.wallet.blockchain_key_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:blockchain_key][:desc] }
          requires :name,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:name][:desc] }
          requires :address,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:address][:desc] }
          optional :currencies,
                   values: { value: ->(v) { Array.wrap(v).all? { |value| value.in? ::Currency.codes } }, message: 'admin.wallet.currency_doesnt_exist' },
                   types: [String, Array], coerce_with: ->(c) { [*c] },
                   as: :currency_ids,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
          # @deprecated Please use `currencies` field
          optional :currency,
                   values: { value: -> { ::Currency.codes }, message: 'admin.wallet.currency_doesnt_exist' },
                   as: :currency_ids,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
          requires :kind,
                   values: { value: ::Wallet.kind.values, message: 'admin.wallet.invalid_kind' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:kind][:desc] }
          requires :gateway,
                   values: { value: -> { ::Wallet.gateways.map(&:to_s) }, message: 'admin.wallet.gateway_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:gateway][:desc] }
          exactly_one_of :currencies, :currency, message: 'admin.wallet.missing_currency_or_currencies_fields'
        end
        post '/wallets/new' do
          admin_authorize! :create, Wallet

          wallet = ::Wallet.new(declared(params))
          if wallet.save
            present wallet, with: API::V2::Admin::Entities::Wallet
            status 201
          else
            body errors: wallet.errors.full_messages
            status 422
          end
        end

        desc 'Update wallet.' do
          success API::V2::Admin::Entities::Wallet
        end
        params do
          use :update_wallet_params
          requires :id,
                   type: { value: Integer, message: 'admin.wallet.non_integer_id' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:id][:desc] }
          optional :blockchain_key,
                   values: { value: -> { ::Blockchain.pluck(:key) }, message: 'admin.wallet.blockchain_key_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:blockchain_key][:desc] }
          optional :name,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:name][:desc] }
          optional :address,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:address][:desc] }
          optional :kind,
                   values: { value: ::Wallet.kind.values, message: 'admin.wallet.invalid_kind' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:kind][:desc] }
          optional :gateway,
                   values: { value: -> { ::Wallet.gateways.map(&:to_s) }, message: 'admin.wallet.gateway_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:gateway][:desc] }
          optional :currencies,
                   values: { value: ->(v) { Array.wrap(v).all? { |value| value.in? ::Currency.codes } }, message: 'admin.wallet.currency_doesnt_exist' },
                   types: [String, Array], coerce_with: ->(c) { [*c] },
                   as: :currency_ids,
                   desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
        end
        post '/wallets/update' do
          admin_authorize! :update, Wallet
          wallet = ::Wallet.find(params[:id])

          params[:settings] = wallet.settings.merge(params[:settings]) if params[:settings]
          if wallet.update(declared(params, include_missing: false))
            present wallet, with: API::V2::Admin::Entities::Wallet
          else
            body errors: wallet.errors.full_messages
            status 422
          end
        end

        desc 'Add currency to the wallet' do
          success API::V2::Admin::Entities::Wallet
        end
        params do
          requires :id,
                  type: { value: Integer, message: 'admin.wallet.non_integer_id' },
                  desc: -> { API::V2::Admin::Entities::Wallet.documentation[:id][:desc] }
          requires :currencies,
                  values: { value: ->(v) { Array.wrap(v).all? { |value| value.in? ::Currency.codes } }, message: 'admin.wallet.currency_doesnt_exist' },
                  types: [String, Array], coerce_with: ->(c) { [*c] },
                  desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
        end
        post '/wallets/currencies' do
          wallet = Wallet.find(params[:id])

          params[:currencies].each do |c_id|
            c_w = CurrencyWallet.new(currency_id: c_id, wallet_id: params[:id])
            if c_w.save
              present wallet, with: API::V2::Admin::Entities::Wallet
              status 201
            else
              body errors: c_w.errors.full_messages
              status 422
            end
          end
        end

        desc 'Delete currency from the wallet' do
          success API::V2::Admin::Entities::Wallet
        end
        params do
          requires :id,
                  type: { value: Integer, message: 'admin.wallet.non_integer_id' },
                  desc: -> { API::V2::Admin::Entities::Wallet.documentation[:id][:desc] }
          requires :currencies,
                  values: { value: ->(v) { Array.wrap(v).all? { |value| value.in? ::Currency.codes } }, message: 'admin.wallet.currency_doesnt_exist' },
                  types: [String, Array], coerce_with: ->(c) { [*c] },
                  desc: -> { API::V2::Admin::Entities::Wallet.documentation[:currencies][:desc] }
        end
        delete '/wallets/currencies' do
          wallet = Wallet.find(params[:id])
          params[:currencies].each do |c_id|
            CurrencyWallet.find_by!(currency_id: c_id, wallet_id: params[:id]).destroy!
          end

          present wallet, with: API::V2::Admin::Entities::Wallet
        end
      end
    end
  end
end
