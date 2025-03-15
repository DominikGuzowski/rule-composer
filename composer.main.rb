# typed: strict
# frozen_string_literal: true
require_relative "require"
require_relative "composer/ruleset"
require_relative "composer/rule"

module Test
  class Merchant < T::Struct
    const :token, String
    const :country, String
    const :capabilities, T::Array[String]
  end

  class Payment < T::Struct
    const :currency, String
    const :amount, Integer
    const :merchant, String
    const :buyer_country, String
  end

  class Operation < T::Enum
    enums do
      IN = new("in")
      NI = new("not in")
      EQ = new("=")
      NE = new("≠")
      GT = new(">")
      GE = new("≥")
      LT = new("<")
      LE = new("≤")
    end
  end

  class PaymentAmount < Composer::Rule
    display_name "PaymentAmount"

    fields do
      let :op, Operation, display_name: "Operation"
      let :amount, Integer, display_name: "Transaction Amount"
    end

    sig { params(merchant: Merchant, payment: Payment).returns(T::Boolean) }
    def evaluate(merchant:, payment:)
      case fields.op
      when Operation::EQ, Operation::IN
        return payment.amount == fields.amount
      when Operation::NE, Operation::NI
        return payment.amount != fields.amount
      when Operation::GT
        return payment.amount > fields.amount
      when Operation::GE
        return payment.amount >= fields.amount
      when Operation::LT
        return payment.amount < fields.amount
      when Operation::LE
        return payment.amount <= fields.amount
      else
        return false
      end
    end
  end

  class PaymentCurrency < Composer::Rule
    display_name "PaymentCurrency"

    fields do
      let :op, Operation, display_name: "Operation"
      let :currency, T::Array[String], display_name: "Currencies"
    end

    sig { params(merchant: Merchant, payment: Payment).returns(T::Boolean) }
    def evaluate(merchant:, payment:)
      case fields.op
      when Operation::EQ
        return payment.currency == fields.currency.first
      when Operation::NE
        return payment.currency != fields.currency.first
      when Operation::IN
        return fields.currency.include?(payment.currency)
      when Operation::NI
        return !fields.currency.include?(payment.currency)
      else
        return false
      end
    end
  end

  class BuyerAndMerchantCountry < Composer::Rule
    display_name "BuyerAndMerchantCountry"

    fields do
      let :op, Operation, display_name: "Operation"
    end

    sig { params(merchant: Merchant, payment: Payment).returns(T::Boolean) }
    def evaluate(merchant:, payment:)
      case fields.op
      when Operation::EQ, Operation::IN
        return merchant.country == payment.buyer_country
      when Operation::NE, Operation::NI
        return merchant.country != payment.buyer_country
      else
        return false
      end
    end
  end

  class ExcludeMerchants < Composer::Rule
    display_name "ExcludeMerchants"

    fields do
      let :ids, T::Array[String], display_name: "Merchant IDs"
    end

    sig { params(merchant: Merchant, payment: Payment).returns(T::Boolean) }
    def evaluate(merchant:, payment:)
      !fields.ids.include?(merchant.token) && !fields.ids.include?(payment.merchant)
    end
  end

  class TransactionEvalRuleset < Composer::Ruleset
    sig { override.returns(String) }
    def ruleset
      "TransactionEval"
    end

    rules do
      rule PaymentAmount
      rule PaymentCurrency
      rule BuyerAndMerchantCountry
      rule ExcludeMerchants
    end
  end
end


json_mp = {
  ruleset: 'TransactionEval',
  rules: ['PaymentAmount', 'PaymentCurrency', 'BuyerAndMerchantCountry', 'ExcludeMerchants'],
  expressions: {
    EligibleForFasterSettlement: {
      And: [
        { type: 'rule', rule: 'PaymentAmount', fields: [{name: 'op', type: 'enum', value: 'ge'}, {name: 'amount', type: 'integer', value: 100_00}] },
        { type: 'rule', rule: 'PaymentCurrency', fields: [{name: 'op', type: 'enum', value: 'in'}, {name: 'currency', type: 'array', value: ['eur', 'gbp', 'usd']}] },
        { type: 'rule', rule: 'BuyerAndMerchantCountry', fields: [{name: 'op', type: 'enum', value: 'eq'}] },
        { type: 'rule', rule: 'ExcludeMerchants', fields: [{name: 'ids', type: 'array', value: ["abcs123", "xyz000"]}]},
        { type: "rule", rule: "PaymentAmount", fields: [{name: "op", type: "enum", value: "le"}, {name: "amount", type: "integer", value: 1000000} ]}
      ]
    },
    IneligibleForFasterSettlement: { type: 'rule', rule: 'PaymentAmount', fields: [{name: 'op', type: 'enum', value: 'lt'}, {name: 'amount', type: 'integer', value: 1_000_000_00}] }
  }
}

json_mp_str = JSON.pretty_generate(json_mp)
engine = Test::TransactionEvalRuleset.from_json(json_mp_str)

merchant = Test::Merchant.new(token: "abc123", country: "IE", capabilities: [])
payment = Test::Payment.new(amount: 200_00, buyer_country: "IE", currency: "gbp", merchant: "abc123")

result = engine.evaluate(:EligibleForFasterSettlement, merchant: merchant, payment: payment)
puts "EligibleForFasterSettlement: #{result}"
puts Test::TransactionEvalRuleset.create_ruleset_definition