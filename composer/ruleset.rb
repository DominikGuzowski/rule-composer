# typed: strict
# frozen_string_literal: true
require_relative "../require"
require_relative "resolver"
module Composer
  class Ruleset
    private_class_method :new

    sig { returns(Ruleset) }
    def self.instance
      @instance ||= T.let(new, Ruleset)
      @@registry ||= T.let({}, T::Hash[String, T::Hash[String, T::Class[Rule]]])
      @@registry[@instance.ruleset] ||= T.let({}, T::Hash[String, T::Class[Rule]])
      @instance
    end

    sig { abstract.returns(String) }
    def ruleset; end

    sig { params(block: T.proc.void).void }
    def self.rules(&block)
      block.call
      rules = instance.rule_registry
      set = Set.new
      rules.values.each do |type|
        args = T::Private::Methods.signature_for_method(type.instance_method(:evaluate)).kwarg_types
        signature = {}
        args.each do |k, v|
          signature[k] = v.raw_type
        end
        set.add(signature)
      end

      raise "Rules do not have uniform parameter signatures: #{set.to_a} in Ruleset `#{instance.ruleset}`" if set.size != 1
    end

    sig { params(rule: T::Class[Rule]).void }
    def self.rule(rule)
      rules = instance.rule_registry

      if !rules.key?(rule.rule_name)
        rules[rule.rule_name] = rule
      else
        raise "Duplicate rule: #{rule.rule_name} in #{instance.ruleset}"
      end
    end

    sig { returns(T::Hash[String, T::Class[Rule]]) }
    def rule_registry
      @@registry[ruleset] ||= T.let({}, T::Hash[String, T::Class[Rule]])
    end

    sig { void }
    def self.show_rules
      puts "#{instance.ruleset}: #{instance.rule_registry}"
    end

    sig { returns(String) }
    def self.create_ruleset_definition
      name = instance.ruleset
      rules = instance.rule_registry
      rule_definitions = {}
      rules.keys.each do |key|
        rule_definitions[key] = rules[key].field_spec
      end
      ruleset = {
        ruleset: name,
        rules: rules.keys,
        rule_definition: rule_definitions
      }
      
      JSON.pretty_generate(ruleset)
    end

    sig { params(json: String).returns(Resolver) }
    def self.from_json!(json)
      validate!(json)
      instance.from_h!(JSON.parse(json, symbolize_names: true))
    end

    sig { params(json: String).returns(Resolver) }
    def self.from_json(json)
      instance.from_h(JSON.parse(json, symbolize_names: true))
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Resolver) }
    def from_h!(data)
      resolver = Resolver.new(rules: {}, expressions: {})

      data[:rules].each do |rule|
        resolver.rules[rule] = rule_registry[rule]
      end

      data[:expressions].each do |name, expr|
        resolver.expressions[name] = Expression.new(name, expr, resolver)
      end

      resolver
    end

    sig { params(data: T::Hash[Symbol, T.untyped]).returns(Resolver) }
    def from_h(data)
      resolver = Resolver.new(rules: {}, expressions: {})
      return resolver unless self.class.validate(JSON.pretty_generate(data))

      data[:rules].each do |rule|
        resolver.rules[rule] = rule_registry[rule]
      end

      data[:expressions].each do |name, expr|
        resolver.expressions[name] = Expression.new(name, expr, resolver)
      end

      resolver
    end

    sig { params(json: String).returns(T::Boolean) }
    def self.validate(json)
      begin
        validate!(json)
        return true
      rescue => err
        puts err
        return false
      end
    end

    sig { params(json: String).void }
    def self.validate!(json)
      data = JSON.parse(json, symbolize_names: true)
      raise "No rules defined in JSON" unless data.key?(:rules)
      raise "No expressions defined in JSON" unless data.key?(:expressions)
      raise "Provided ruleset does not match the implementation: #{data[:ruleset]} != #{instance.ruleset}" unless instance.ruleset == data[:ruleset]
      
      data[:rules].each do |rule|
        raise "Rule #{rule} is undefined for #{instance.ruleset} -> #{instance.rule_registry.keys}" unless instance.rule_registry.key?(rule)
      end

      expression_names = data[:expressions].keys
      expressions = {}
      data[:expressions].each do |name, expr|
        instance.validate_expression(expr, expression_names)
        expressions[name] = expr
      end

      expression_names.each do |expr|
        instance.ensure_no_cyclic_expressions(expr, expressions, [])
      end
    end

    sig { params(expr: T::Hash[Symbol, T.untyped], exprs: T::Array[Symbol]).void }
    def validate_expression(expr, exprs)
      if !expr.keys.one? && expr.keys.all? { |k| [:And, :Or, :Not].include?(k) }
        raise "Ambiguous expression, each expression may only contain one of [And, Or, Not], found: [#{expr.keys.join(", ")}]"
      end

      if expr.key?(:And)
        raise "Redundant empty And expression found #{expr}" if expr[:And].length == 0
        raise "`And` expression has only one component, please remove the `And` operand: `#{expr}" if expr[:And].one?
        expr[:And].each do |ex|
          validate_expression(ex, exprs)
        end
        return
      end

      if expr.key?(:Or)
        raise "Redundant empty Or expression found #{expr}" if expr[:Or].length == 0
        raise "`Or` expression has only one component, please remove the `Or` operand: `#{expr}" if expr[:Or].one?

        expr[:Or].each do |ex|
          validate_expression(ex, exprs)
        end
        return
      end

      if expr.key?(:Not)
        raise "Redundant empty Not expression found #{expr}" if expr[:Not].keys.length == 0
        validate_expression(expr[:Not], exprs)
        return
      end

      if expr.key?(:rule)
        raise "Unknown rule reference #{expr[:rule]} for #{ruleset}: #{rule_registry.keys}" unless rule_registry.key?(expr[:rule])
        rule = rule_registry[expr[:rule]]
        expr[:fields].each do |f|
          info = rule.field_info.find { |i| i.type == f[:type].to_sym && i.name == f[:name].to_sym }
          raise "Invalid field #{f} for rule #{rule.rule_name}, expected any of #{rule.field_info.map(&:to_h)}" if info.nil?
          fields = {}
          expr[:fields].map do |field|
            fields[field[:name].to_sym] = field[:value]
          end
          rule.field_info.each do |field|
            if field.type == :enum
              raise "Unknown enum value for field `#{field.name}`, expected one of #{field.options} but got `#{fields[field.name]}`" unless field.options&.include?(fields[field.name])
            end
          end
        end
        return
      end

      if expr.key?(:expr)
        case expr[:expr]
        when Hash
          raise "Redundant expression nesting, please replace the outer expression with inner: `#{expr}` -> `#{expr[:expr]}`" if expr[:expr].key?(:type)
          
          validate_expression(expr[:expr], exprs)
        when String
          raise "Unknown reference to expression #{expr[:expr]}. Expected any of: #{exprs}" unless exprs.include?(expr[:expr].to_sym)
        else
          T.absurd(expr[:expr])
        end
        return
      end

      raise "Unknown expression pattern: #{expr}"
    end

    sig { params(expr: Symbol, exprs: T::Hash[Symbol, T.untyped], path: T::Array[Symbol]).void }
    def ensure_no_cyclic_expressions(expr, exprs, path)
      if exprs.key?(expr)
        [:And, :Or, :Not].each do |k|
          if exprs[expr].key?(k)
            exprs[expr][k].each do |e|
              next if e.key?(:rule)

              if e[:expr].is_a?(String)
                name = e[:expr].to_sym
                raise "Found cyclic reference to expression #{name}: #{path.join("->")}->#{name}" if path.include?(name)
                ensure_no_cyclic_expressions(name, exprs, path + [name])
                next
              end
              
              key = T.must(e[:expr].keys.first)
              if key == :Not
                traverse_expressions(e[:expr][key], exprs, path)
              else
                e[:expr][key].select { |ex| ex[:type] == 'expr' }.each do |ex|
                  traverse_expressions(ex, exprs, path)
                end
              end
            end
          end
        end
      end
    end

    sig { params(current: T::Hash[Symbol, T.untyped], exprs: T::Hash[Symbol, T.untyped], path: T::Array[Symbol]).void }
    def traverse_expressions(current, exprs, path)
      return if current.key?(:rule)

      if current.key?(:expr)
        case current[:expr]
        when String
          name = current[:expr].to_sym
          ensure_no_cyclic_expressions(name, exprs, path + [name])
          return
        when Hash
          key = T.must(current[:expr].keys.first)
          traverse_expressions(current[:expr][key], exprs, path)
          return
        end
      end

      [:And, :Or, :Not].each do |key|
        if current.key?(key)
          expr[:expr][key].select { |e| e[:type] == 'expr' }.each do |expr|
            traverse_expressions(expr, exprs, path)
          end
        end
      end
    end
  end
end