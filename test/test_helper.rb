# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'crossbeams/menu_migrations'

require 'minitest/autorun'
require 'minitest/rg'
ENV['TEST_RUN'] = 'y'
