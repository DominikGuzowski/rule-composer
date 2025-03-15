# require.rb or environment.rb

# Load Bundler and require all gems from the Gemfile
require 'bundler/setup'
Bundler.require(:default)

# Require Sorbet and its runtime
require 'sorbet-runtime'

# dependencies
require 'json'
require 'set'


# Optionally, initialize Sorbet runtime type checking
T::Configuration.default_checked_level = :always

# Add any other project-wide setup or configuration here
Object.include(T::Sig)
Object.extend(T::Helpers)