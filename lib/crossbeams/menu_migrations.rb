# frozen_string_literal: true

require 'crossbeams/menu_migrations/version'
require 'crossbeams/menu_migrations/migrator'

module Crossbeams
  # Migrate menu items for Crossbeams framework projects
  module MenuMigrations
    class Error < StandardError; end
  end
end
