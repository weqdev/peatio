# encoding: UTF-8
# frozen_string_literal: true

module API
  module V2
    module Admin
      class Currencies < Grape::API
        helpers ::API::V2::Admin::Helpers
        helpers do
          # Collection of shared params, used to
          # generate required/optional Grape params.
          OPTIONAL_CURRENCY_PARAMS ||= {
            name: { desc: -> { API::V2::Admin::Entities::Currency.documentation[:name][:desc] } },
            deposit_fee: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_deposit_fee' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.invalid_deposit_fee' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:deposit_fee][:desc] }
            },
            min_deposit_amount: {
              type: { value: BigDecimal, message: 'admin.currency.min_deposit_amount' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.min_deposit_amount' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:min_deposit_amount][:desc] }
            },
            min_collection_amount: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_min_collection_amount' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.invalid_min_collection_amount' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:min_collection_amount][:desc] }
            },
            withdraw_fee: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_withdraw_fee' },
              values: { value: -> (p){ p >= 0  }, message: 'admin.currency.ivalid_withdraw_fee' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:withdraw_fee][:desc] }
            },
            min_withdraw_amount: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_min_withdraw_amount' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.invalid_min_withdraw_amount' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:min_withdraw_amount][:desc] }
            },
            withdraw_limit_24h: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_withdraw_limit_24h' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.invalid_withdraw_limit_24h' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:withdraw_limit_24h][:desc] }
            },
            withdraw_limit_72h: {
              type: { value: BigDecimal, message: 'admin.currency.non_decimal_withdraw_limit_72h' },
              values: { value: -> (p){ p >= 0 }, message: 'admin.currency.invalid_withdraw_limit_72h' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:withdraw_limit_72h][:desc] }
            },
            position: {
              type: { value: Integer, message: 'admin.currency.non_integer_position' },
              default: 0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:position][:desc] }
            },
            options: {
              type: { value: JSON, message: 'admin.currency.non_json_options' },
              default: 0.0,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:options][:desc] }
            },
            visible: {
              type: { value: Boolean, message: 'admin.currency.non_boolean_visible' },
              default: true,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:visible][:desc] }
            },
            deposit_enabled: {
              type: { value: Boolean, message: 'admin.currency.non_boolean_deposit_enabled' },
              default: true,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:deposit_enabled][:desc] }
            },
            withdrawal_enabled: {
              type: { value: Boolean, message: 'admin.currency.non_boolean_withdrawal_enabled' },
              default: true,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:withdrawal_enabled][:desc] }
            },
            precision: {
              type: { value: Integer, message: 'admin.currency.non_integer_base_precision' },
              default: 8,
              desc: -> { API::V2::Admin::Entities::Currency.documentation[:precision][:desc] }
            },
            icon_url: { desc: -> { API::V2::Admin::Entities::Currency.documentation[:icon_url][:desc] } },
            description: { desc: -> { API::V2::Admin::Entities::Currency.documentation[:description][:desc] } },
            homepage: { desc: -> { API::V2::Admin::Entities::Currency.documentation[:homepage][:desc] } },
          }

          params :create_currency_params do
            OPTIONAL_CURRENCY_PARAMS.each do |key, params|
              optional key, params
            end
          end

          params :update_currency_params do
            OPTIONAL_CURRENCY_PARAMS.each do |key, params|
              optional key, params.except(:default)
            end
          end
        end

        desc 'Get list of currencies',
          is_array: true,
          success: API::V2::Admin::Entities::Currency
        params do
          use :currency_type
          use :pagination
          use :ordering
        end
        get '/currencies' do
          admin_authorize! :read, Currency

          # If param type is not given variable types will be nil, and ransack will return full collection
          if params[:type].present?
            types = params[:type] == 'fiat'  ? params[:type] : Currency::CRYPTO_TYPES
          end

          search = Currency.ransack(type_in: types)
          search.sorts = "#{params[:order_by]} #{params[:ordering]}"

          present paginate(search.result), with: API::V2::Admin::Entities::Currency
        end

        desc 'Get a currency.' do
          success API::V2::Admin::Entities::Currency
        end
        params do
          requires :code,
                   type: String,
                   values: { value: -> { Currency.codes(bothcase: true) }, message: 'admin.currency.doesnt_exist'},
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:code][:desc] }
        end
        get '/currencies/:code' do
          admin_authorize! :read, Currency

          present Currency.find(params[:code]), with: API::V2::Admin::Entities::Currency
        end

        desc 'Create new currency.' do
          success API::V2::Admin::Entities::Currency
        end
        params do
          use :create_currency_params
          requires :code,
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:code][:desc] }
          requires :symbol,
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:symbol][:desc] }
          optional :type,
                   values: { value: ::Currency.types.map(&:to_s), message: 'admin.currency.invalid_type' },
                   default: 'coin',
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:type][:desc] }
          optional :base_factor,
                   type: { value: Integer, message: 'admin.currency.non_integer_base_factor' },
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:base_factor][:desc] }
          optional :subunits,
                   type: { value: Integer, message: 'admin.currency.non_integer_subunits' },
                   values: { value: (0..18), message: 'admin.currency.invalid_subunits' },
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:subunits][:desc] }
          given type: ->(val) { val == 'coin' || val == 'token' } do
            requires :blockchain_key,
                     values: { value: -> { ::Blockchain.pluck(:key) }, message: 'admin.currency.blockchain_key_doesnt_exist' },
                     desc: -> { API::V2::Admin::Entities::Currency.documentation[:blockchain_key][:desc] }
          end
          mutually_exclusive :base_factor, :subunits, message: 'admin.currency.one_of_base_factor_subunits_fields'
        end
        post '/currencies/new' do
          admin_authorize! :create, Currency

          currency = Currency.new(declared(params, include_missing: false))
          if currency.save
            present currency, with: API::V2::Admin::Entities::Currency
            status 201
          else
            body errors: currency.errors.full_messages
            status 422
          end
        end

        desc 'Update currency.' do
          success API::V2::Admin::Entities::Currency
        end
        params do
          use :update_currency_params
          requires :code,
                   values: { value: -> { ::Currency.codes }, message: 'admin.currency.doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:code][:desc] }
          optional :symbol,
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:symbol][:desc] }
          optional :blockchain_key,
                   values: { value: -> { ::Blockchain.pluck(:key) }, message: 'admin.currency.blockchain_key_doesnt_exist' },
                   desc: -> { API::V2::Admin::Entities::Currency.documentation[:blockchain_key][:desc] }
        end
        post '/currencies/update' do
          admin_authorize! :update, Currency, params.except(:code)

          currency = Currency.find(params[:code])
          if currency.update(declared(params, include_missing: false))
            present currency, with: API::V2::Admin::Entities::Currency
          else
            body errors: currency.errors.full_messages
            status 422
          end
        end
      end
    end
  end
end
