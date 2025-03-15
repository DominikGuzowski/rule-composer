# typed: strict
# frozen_string_literal: true
require_relative "../require"
require_relative "rule"
require_relative "expression"

module Composer
  class Resolver < T::Struct
    const :rules, T::Hash[Symbol, T::Class[Rule]]
    const :expressions, T::Hash[Symbol, Expression]

    sig { params(name: Symbol, args: T.untyped).returns(T::Boolean) }
    def evaluate(name, **args)
      if rules.keys.empty? || expressions.keys.empty?
        puts "Empty resolver: The ruleset and expression evaluation likely failed."
        return false
      end

      expressions[name].evaluate(**args)
    end
  end
end