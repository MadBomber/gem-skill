# frozen_string_literal: true

module Gem::Skill
  # Reads numeric settings from environment variables. A value that does not
  # parse falls back to the default with a warning, instead of silently
  # becoming 0 the way String#to_i / #to_f would.
  module Env
    # Decimal integer from +env[name]+, or +default+ when unset or unparseable.
    def self.integer(name, default, env = ENV)
      read(name, default, env) { |value| Integer(value, 10, exception: false) }
    end

    # Float from +env[name]+, or +default+ when unset or unparseable.
    def self.float(name, default, env = ENV)
      read(name, default, env) { |value| Float(value, exception: false) }
    end

    def self.read(name, default, env)
      value = env[name]
      return default if value.nil?

      parsed = yield(value)
      return parsed unless parsed.nil?

      warn "gem-skill: ignoring #{name}=#{value.inspect} (not a number); using #{default}"
      default
    end
    private_class_method :read
  end
end
