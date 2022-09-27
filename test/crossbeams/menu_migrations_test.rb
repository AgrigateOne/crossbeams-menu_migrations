# frozen_string_literal: true

require 'test_helper'

class Crossbeams::MenuMigrationsTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Crossbeams::MenuMigrations::VERSION
  end

  def test_add_drop_func
    migration = Crossbeams::MenuMigrations::Migrator::SimpleMigration.new('Appname', dry_run: true)
    migration.up = -> { add_functional_area 'Basic' }
    migration.down = -> { drop_functional_area 'Basic' }
    up = ["BEGIN;",
          "INSERT INTO functional_areas (functional_area_name, rmd_menu) VALUES('Basic', false);",
          "INSERT INTO menu_migrations (filename) VALUES('a_file');",
          "COMMIT;"]

    down = ["BEGIN;",
            "DELETE FROM program_functions_users WHERE program_function_id IN (SELECT id FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Basic')));",
            "DELETE FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Basic'));",
            "DELETE FROM programs_webapps WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Basic'));",
            "DELETE FROM programs_users WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Basic'));",
            "DELETE FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Basic');",
            "DELETE FROM functional_areas WHERE functional_area_name ='Basic';",
            "DELETE FROM menu_migrations WHERE filename = 'a_file';",
            "COMMIT;"]
    assert_equal up, migration.apply({}, :up, 'a_file')
    assert_equal down, migration.apply({}, :down, 'a_file')
  end
end
