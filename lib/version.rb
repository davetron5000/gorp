module Gorp
  module VERSION #:nodoc:
    MAJOR = 0
    MINOR = 16
    TINY  = 5

    STRING = [MAJOR, MINOR, TINY].join('.')
  end
end unless defined?(Gorp::VERSION)
