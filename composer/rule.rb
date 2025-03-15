# typed: strict
# frozen_string_literal: true
require_relative "../require"
require_relative "field_definition"

module Composer
  class Rule
    extend T::Sig
    extend T::Helpers
    abstract!

    class << self
      extend T::Sig

      sig { returns(String) }
      def rule_name
        @rule_name ||= name.split('::').last
      end

      sig { params(name: String).void }
      def display_name(name)
        @rule_name = name
      end

      sig { returns(T::Array[FieldDefinition::FieldSpec]) }
      def field_info
        const_get(:Fields)&.field_info || []
      end

      sig { params(block: T.proc.void).void }
      def fields(&block)
        fields_class = create_fields_class(&block)
        const_set(:Fields, fields_class)
      end

      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(T.self_type) }
      def from_hash(hash)
        fields_data = hash.dup
        field_info.each do |field|
          if field.type == :enum
            prop = const_get(:Fields).props[field.name]
            enum_class = prop[:type]
            fields_data[field.name] = enum_class.deserialize(fields_data[field.name])
          end
        end
        fields_struct = const_get(:Fields).new(fields_data)
        new(fields_struct)
      end

      sig { params(json_str: String).returns(T.self_type) }
      def from_json(json_str)
        data = JSON.parse(json_str, symbolize_names: true)
        fields_data = data[:fields].to_h { |field| [field[:name].to_sym, field[:value]] }
        from_hash(fields_data)
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def spec
        {
          name: rule_name,
          fields: field_info.map(&:to_h)
        }
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def field_spec
        field_info.map(&:to_h)
      end

      private

      sig { params(block: T.proc.void).returns(Class) }
      def create_fields_class(&block)
        Class.new(T::Struct) do
          extend FieldDefinition

          sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
          def to_h
            self.class.field_info.map do |field|
              {
                name: field.name.to_s,
                type: field.type.to_s,
                value: send(field.name)
              }
            end
          end

          class_exec(&block)
        end
      end
    end

    sig { returns(T::Struct) }
    attr_reader :fields

    sig { params(fields: T::Struct).void }
    def initialize(fields)
      @fields = fields
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_h
      {
        type: 'rule',
        rule: rule_name,
        fields: fields.to_h
      }
    end

    sig { returns(String) }
    def to_json
      JSON.pretty_generate(to_h)
    end
  end
end