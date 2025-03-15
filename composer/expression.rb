# typed: strict
# frozen_string_literal: true
require_relative "../require"

module Composer
  class Expression
    sig { params(name: Symbol, expression: T.untyped, resolver: Resolver).void }
    def initialize(name, expression, resolver)
      @name = name
      @expression = expression
      @resolver = resolver
    end

    sig { params(args: T.untyped).returns(T::Boolean) }
    def evaluate(**args)
      evaluate_expression(@expression, **args)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        :name => @name,
        :expression => @expression
      }
    end

    sig { returns(String) }
    def to_json
      JSON.pretty_generate(to_h)
    end

    private

    sig { params(expression: T.untyped, args: T.untyped).returns(T::Boolean) }
    def evaluate_expression(expression, **args)
      case expression
      when Hash
        evaluate_hash_expression(expression, **args)
      else
        false
      end
    end

    sig { params(expression: T::Hash[Symbol, T.untyped], args: T.untyped).returns(T::Boolean) }
    def evaluate_hash_expression(expression, **args)
      if expression.key?(:And)
        expression[:And].all? { |expr| evaluate_expression(expr, **args) }
      elsif expression.key?(:Or)
        expression[:Or].any? { |expr| evaluate_expression(expr, **args) }
      elsif expression.key?(:Not)
        !evaluate_expression(expression[:Not], **args)
      elsif expression[:type] == 'rule'
        evaluate_rule(expression, **args)
      else
        evaluate_nested_expression(expression, **args)
      end
    end

    sig { params(expression: T::Hash[Symbol, T.untyped], args: T.untyped).returns(T::Boolean) }
    def evaluate_nested_expression(expression, **args)
      case expression[expression[:type].to_sym]
      when String
        @resolver.evaluate(expression[:expr].to_sym, **args)
      when Hash
        evaluate_expression(expression[:expr], **args)
      else
        false
      end
    end

    sig { params(rule_expression: T::Hash[Symbol, T.untyped], args: T.untyped).returns(T::Boolean) }
    def evaluate_rule(rule_expression, **args)
      rule_name = rule_expression[:rule]
      fields_data = rule_expression[:fields].to_h { |field| [field[:name].to_sym, field[:value]] }

      rule_class = @resolver.rules[rule_name]
      rule = rule_class.from_hash(fields_data)

      rule.evaluate(**args)
    end
  end
end