# frozen_string_literal: true

require 'test_helper'

class Crossbeams::MenuMigrationsTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Crossbeams::MenuMigrations::VERSION
  end

  def script_up(ar)
    ar.unshift('BEGIN;').push("INSERT INTO menu_migrations (filename) VALUES('a_file');").push('COMMIT;')
  end

  def script_down(ar)
    ar.unshift('BEGIN;').push("DELETE FROM menu_migrations WHERE filename = 'a_file';").push('COMMIT;')
  end

  def add_func
    "INSERT INTO functional_areas (functional_area_name, rmd_menu) VALUES('Func', false);"
  end

  def drop_func_pf_users
    "DELETE FROM program_functions_users WHERE program_function_id IN (SELECT id FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Func')));"
  end

  def drop_func_pf
    "DELETE FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Func'));"
  end

  def drop_func_pw
    "DELETE FROM programs_webapps WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Func'));"
  end

  def drop_func_pu
    "DELETE FROM programs_users WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Func'));"
  end

  def drop_func_p
    "DELETE FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='Func');"
  end

  def drop_func_f
    "DELETE FROM functional_areas WHERE functional_area_name ='Func';"
  end

  def add_prog
    <<~SQL
      INSERT INTO programs (program_name, program_sequence, functional_area_id)
      VALUES ('Prog', 1, (SELECT id FROM functional_areas WHERE functional_area_name = 'Func'));
      INSERT INTO programs_webapps (program_id, webapp)
      VALUES ((SELECT id FROM programs WHERE program_name = 'Prog'
               AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name = 'Func')), 'Appname');
    SQL
  end

  def drop_prog_pf_users
    <<~SQL
      DELETE FROM program_functions_users
      WHERE program_function_id IN (
        SELECT id
        FROM program_functions
        WHERE program_id = (SELECT id FROM programs WHERE program_name = 'Prog' AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name = 'Func')));
    SQL
  end

  def drop_prog_pf
    <<~SQL
      DELETE FROM program_functions
      WHERE program_id = (
        SELECT id
        FROM programs
        WHERE program_name = 'Prog'
          AND functional_area_id = (
            SELECT id
            FROM functional_areas
            WHERE functional_area_name ='Func'));
    SQL
  end

  def drop_prog_pw
    <<~SQL
      DELETE FROM programs_webapps
      WHERE program_id = (
        SELECT id
        FROM programs
        WHERE program_name = 'Prog'
          AND functional_area_id = (
            SELECT id
            FROM functional_areas
            WHERE functional_area_name ='Func'));
    SQL
  end

  def drop_prog_pu
    <<~SQL
      DELETE FROM programs_users
      WHERE program_id = (
        SELECT id
        FROM programs
        WHERE program_name = 'Prog'
          AND functional_area_id = (
            SELECT id
            FROM functional_areas
            WHERE functional_area_name ='Func'));
    SQL
  end

  def drop_prog_p
    <<~SQL
      DELETE FROM programs
      WHERE program_name = 'Prog'
        AND functional_area_id = (
          SELECT id
          FROM functional_areas
          WHERE functional_area_name ='Func');
    SQL
  end


  def test_add_drop_func
    migration = Crossbeams::MenuMigrations::Migrator::SimpleMigration.new('Appname', dry_run: true)
    migration.up = -> { add_functional_area 'Func' }
    migration.down = -> { drop_functional_area 'Func' }
    up = script_up([add_func])

    down = script_down([drop_func_pf_users,
                        drop_func_pf,
                        drop_func_pw,
                        drop_func_pu,
                        drop_func_p,
                        drop_func_f])
    assert_equal up, migration.apply({}, :up, 'a_file')
    assert_equal down, migration.apply({}, :down, 'a_file')
  end

  def test_add_drop_prog
    migration = Crossbeams::MenuMigrations::Migrator::SimpleMigration.new('Appname', dry_run: true)
    migration.up = -> { add_program 'Prog', functional_area: 'Func' }
    migration.down = -> { drop_program 'Prog', functional_area: 'Func' }
    up = script_up([add_prog])

    down = script_down([drop_prog_pf_users,
                        drop_prog_pf,
                        drop_prog_pw,
                        drop_prog_pu,
                        drop_prog_p])
    assert_equal up, migration.apply({}, :up, 'a_file')
    assert_equal down, migration.apply({}, :down, 'a_file')
  end
end
