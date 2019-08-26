# encoding: utf-8
require 'time'

require 'ruby_ami/response'

module RubyAMI
  class Event < Response
    VAR_SET_ENCODING_PATTERN = /\\[abfnrtv\\'"?]/.freeze
    VAR_SET_ENCODING_MAP = {
      '\\a'  => "\a",
      '\\b'  => "\b",
      '\\f'  => "\f",
      '\\n'  => "\n",
      '\\r'  => "\r",
      '\\t'  => "\t",
      '\\v'  => "\v",
      '\\\\' => '\\',
      "\\'"  => "'",
      '\\"'  => '"',
      '\\?'  => '?'
    }.freeze

    attr_reader :name, :receipt_time

    def initialize(name, headers = {})
      @receipt_time = DateTime.now
      super headers
      @name = name
    end

    # @return [DateTime, nil] the timestamp of the event, or nil if none is available
    def timestamp
      return unless headers['Timestamp']
      DateTime.strptime headers['Timestamp'], '%s'
    end

    # @return [DateTime] the best known timestamp for the event. Either its timestamp if specified, or its receipt time if not.
    def best_time
      timestamp || receipt_time
    end

    # Set a Header value
    # @override RubyAMI::Response
    def []=(key,value)
      super key, parse_raw_value(key, value)
    end

    def parse_raw_value(key, value)
      return parse_raw_varset_value value if parse_raw_varset_value? key
      value
    end

    def parse_raw_varset_value(value)
      value.gsub VAR_SET_ENCODING_PATTERN, VAR_SET_ENCODING_MAP
    end

    def parse_raw_varset_value?(key)
      @name.eql?('VarSet') && key.eql?('Value')
    end

    def inspect_attributes
      [:name] + super
    end
  end
end # RubyAMI
