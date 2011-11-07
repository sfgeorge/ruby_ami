%w{
  active_support/dependencies/autoload
  active_support/core_ext/object/blank
  active_support/core_ext/numeric/time
  active_support/core_ext/numeric/bytes
  active_support/hash_with_indifferent_access

  uuidtools
  eventmachine
  future-resource
  logger
  girl_friday
  countdownlatch

  ruby_ami/metaprogramming
}.each { |f| require f }

class Logger
  alias :trace :debug
end

module RubyAMI
  extend ActiveSupport::Autoload

  autoload :Action
  autoload :Client
  autoload :Error
  autoload :Event
  autoload :Lexer
  autoload :Response
  autoload :Stream
  autoload :Version
end
