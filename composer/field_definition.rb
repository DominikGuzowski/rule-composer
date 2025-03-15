# typed: strict
# frozen_string_literal: true
require_relative "../require"

module Composer
  module FieldDefinition
    extend T::Sig

    class FieldSpec < T::Struct
      const :name, Symbol
      const :type, Symbol
      const :display_name, String
      const :options, T.nilable(T::Array[String])

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        if options.nil?
          {
            name: name.to_s,
            display_name: display_name,
            type: type.to_s
          }
        else
          {
            name: name.to_s,
            display_name: display_name,
            type: type.to_s,
            options: options
          }
        end
      end

      sig { override.returns(String) }
      def to_s
        to_h.to_s
      end
    end

    sig { returns(T::Array[FieldSpec]) }
    def field_info
      @field_info ||= []
    end

    sig do
      params(
        name: Symbol,
        type: T.untyped,
        display_name: T.nilable(String),
        block: T.nilable(T.proc.void)
      ).void
    end
    def let(name, type, display_name: nil, &block)
      @field_info ||= T.let([], T::Array[FieldSpec])

      type = normalize_type(type)
      type_name = extract_type_name(type)

      options = type_name == :enum ? type.raw_type.values.map(&:serialize) : nil
      disp_name = display_name || name.to_s
      @field_info << FieldSpec.new(name: name, type: type_name, display_name: disp_name, options: options)
      prop(name, type, &block)
    end

    private

    sig { params(type: T.untyped).returns(T.untyped) }
    def normalize_type(type)
      if type.is_a?(Class) && type <= T::Enum
        T::Types::Simple.new(type)
      else
        type
      end
    end

    sig { params(type: T.untyped).returns(Symbol) }
    def extract_type_name(type)
      if type.is_a?(T::Types::Simple) && type.raw_type <= T::Enum
        :enum
      else
        type.to_s.downcase.gsub(/(t::)|(\[.*\])/, '').to_sym
      end
    end
  end
end