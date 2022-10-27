# frozen_string_literal: true

module Crossbeams
  module MenuMigrations
    # Migrate menu items (largely based on the code for Sequel's migration)
    class Migrator # rubocop:disable Metrics/ClassLength
      class Error < StandardError; end

      MIGRATION_FILE_PATTERN = /\A(\d+)_.+\.rb\z/i.freeze

      # Mutex used around migration file loading
      MUTEX = Mutex.new

      def self.migrations
        @migrations ||= []
      end

      # Migration class - applies the migration steps to the db.
      class SimpleMigration # rubocop:disable Metrics/ClassLength
        # Proc used for the down action
        attr_accessor :down

        # Proc used for the up action
        attr_accessor :up

        def initialize(webapp, dry_run: false)
          @webapp = webapp
          @script = nil
          @dry_run = dry_run
        end

        # Apply the appropriate block to generate
        # a script to run within a transaction.
        def apply(db, direction, filename)
          raise(ArgumentError, "Invalid migration direction specified (#{direction.inspect})") unless %i[up down].include?(direction)

          @script = ['BEGIN;']
          prok = public_send(direction)
          return unless prok

          instance_exec(&prok)
          @script << if direction == :up
                       "INSERT INTO menu_migrations (filename) VALUES('#{filename}');"
                     else
                       "DELETE FROM menu_migrations WHERE filename = '#{filename}';"
                     end
          @script << 'COMMIT;'

          puts "- #{direction == :up ? 'Applying' : 'Reversing'}: #{filename}" unless ENV['TEST_RUN']
          if @dry_run
            puts @script.join("\n") unless ENV['TEST_RUN']
            @script
          else
            db.execute(@script.join("\n"))
          end
        end

        # -- DSL methods
        # ------------------------------------------------------------------
        def add_functional_area(key, rmd_menu: false)
          check_string!(key)
          @script << "INSERT INTO functional_areas (functional_area_name, rmd_menu) VALUES('#{key}', #{rmd_menu});"
        end

        def drop_functional_area(key)
          check_string!(key)
          @script << "DELETE FROM program_functions_users WHERE program_function_id IN (SELECT id FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{key}')));"
          @script << "DELETE FROM program_functions WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{key}'));"
          @script << "DELETE FROM programs_webapps WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{key}'));"
          @script << "DELETE FROM programs_users WHERE program_id IN (SELECT id FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{key}'));"
          @script << "DELETE FROM programs WHERE functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{key}');"
          @script << "DELETE FROM functional_areas WHERE functional_area_name ='#{key}';"
        end

        F_KEYS = %i[rmd_menu rename].freeze
        def change_functional_area(key, options = {})
          check_string!(key)
          raise Error, "Cannot change functional area #{key} - no changes given" if options.empty?
          raise Error, "Cannot change functional area #{key} - invalid options" unless options.keys.all? { |o| F_KEYS.include?(o) }

          changes = []
          changes << "rmd_menu = #{options[:rmd_menu]}" unless options[:rmd_menu].nil?
          changes << "functional_area_name = '#{options[:rename]}'" if options[:rename]
          @script << "UPDATE functional_areas SET #{changes.join(', ')} WHERE functional_area_name ='#{key}';"
        end

        def match_functional_area_id(functional_area)
          "functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name = '#{functional_area}')"
        end

        def match_program_id(program, functional_area)
          "program_id = (SELECT id FROM programs WHERE program_name = '#{program}' AND #{match_functional_area_id(functional_area)})"
        end

        def add_program(key, functional_area:, seq: 1)
          check_string!(key, functional_area)
          @script << <<~SQL
            INSERT INTO programs (program_name, program_sequence, functional_area_id)
            VALUES ('#{key}', #{seq}, (SELECT id FROM functional_areas WHERE functional_area_name = '#{functional_area}'));
            INSERT INTO programs_webapps (program_id, webapp)
            VALUES ((SELECT id FROM programs WHERE program_name = '#{key}'
                     AND #{match_functional_area_id(functional_area)}), '#{@webapp}');
          SQL
        end

        def drop_program(key, functional_area:)
          check_string!(key, functional_area)
          @script << <<~SQL
            DELETE FROM program_functions_users
            WHERE program_function_id IN (
              SELECT id
              FROM program_functions
              WHERE #{match_program_id(key, functional_area)});
          SQL
          @script << <<~SQL
            DELETE FROM program_functions
            WHERE program_id = (
              SELECT id
              FROM programs
              WHERE program_name = '#{key}'
                AND functional_area_id = (
                  SELECT id
                  FROM functional_areas
                  WHERE functional_area_name ='#{functional_area}'));
          SQL
          @script << <<~SQL
            DELETE FROM programs_webapps
            WHERE program_id = (
              SELECT id
              FROM programs
              WHERE program_name = '#{key}'
                AND functional_area_id = (
                  SELECT id
                  FROM functional_areas
                  WHERE functional_area_name ='#{functional_area}'));
          SQL
          @script << <<~SQL
            DELETE FROM programs_users
            WHERE program_id = (
              SELECT id
              FROM programs
              WHERE program_name = '#{key}'
                AND functional_area_id = (
                  SELECT id
                  FROM functional_areas
                  WHERE functional_area_name ='#{functional_area}'));
          SQL
          @script << <<~SQL
            DELETE FROM programs
            WHERE program_name = '#{key}'
              AND functional_area_id = (
                SELECT id
                FROM functional_areas
                WHERE functional_area_name ='#{functional_area}');
          SQL
        end

        P_KEYS = %i[functional_area seq rename].freeze
        def change_program(key, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
          raise Error, "Cannot change program #{key} - no changes given" if options.empty? || options.length == 1
          raise Error, "Cannot change program #{key} - no functional area given" unless options[:functional_area]
          raise Error, "Cannot change program #{key} - invalid options" unless options.keys.all? { |o| P_KEYS.include?(o) }

          check_string!(key, options[:functional_area])

          changes = []
          changes << "program_sequence = #{options[:seq]}" if options[:seq]
          changes << "program_name = '#{options[:rename]}'" if options[:rename]
          @script << "UPDATE programs SET #{changes.join(', ')} WHERE program_name = '#{key}' AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{options[:functional_area]}');"
        end

        def add_program_function(key, functional_area:, program:, url:, seq: 1, group: nil, restricted: false, show_in_iframe: false, hide_if_const_true: nil, hide_if_const_false: nil) # rubocop:disable Metrics/ParameterLists
          check_string!(key, functional_area, program, group)
          group_name = "'#{group}'" if group
          if hide_if_const_true
            head_true = ', hide_if_const_true'
            hide_true = ", '#{hide_if_const_true}'" if hide_if_const_true
          end
          if hide_if_const_false
            head_false = ', hide_if_const_false'
            hide_false = ", '#{hide_if_const_false}'"
          end
          @script << <<~SQL
            INSERT INTO program_functions (program_id, program_function_name, url, program_function_sequence,
                                           group_name, restricted_user_access, show_in_iframe#{head_true}#{head_false})
            VALUES ((SELECT id FROM programs WHERE program_name = '#{program}'
                      AND functional_area_id = (SELECT id FROM functional_areas
                                                WHERE functional_area_name = '#{functional_area}')),
                    '#{key}', '#{url}', #{seq}, #{group_name || 'NULL'}, #{restricted}, #{show_in_iframe}#{hide_true}#{hide_false});
          SQL
        end

        def drop_program_function(key, functional_area:, program:, match_group: nil)
          check_string!(key, functional_area, program, match_group)
          group_where = if match_group
                          " AND group_name = '#{match_group}'"
                        else
                          ' AND group_name IS NULL'
                        end
          @script << "DELETE FROM program_functions_users WHERE program_function_id = (SELECT id FROM program_functions WHERE program_function_name = '#{key}' AND program_id = (SELECT id FROM programs WHERE program_name = '#{program}' AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{functional_area}'))#{group_where});"
          @script << "DELETE FROM program_functions WHERE program_function_name = '#{key}' AND program_id = (SELECT id FROM programs WHERE program_name = '#{program}' AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{functional_area}'))#{group_where};"
        end

        PF_MOVE_KEYS = %i[functional_area program to_program to_functional_area].freeze
        def move_program_function(key, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
          raise Error, "Cannot move program function #{key} - no target program given" if options.empty? || options.length == 2
          raise Error, "Cannot move program function #{key} - no functional area given" unless options[:functional_area]
          raise Error, "Cannot move program function #{key} - no program given" unless options[:program]
          raise Error, "Cannot move program function #{key} - invalid options" unless options.keys.all? { |o| PF_MOVE_KEYS.include?(o) }

          check_string!(key, options[:functional_area], options[:program], options[:to_program], options[:to_functional_area])

          sql = <<~SQL
            UPDATE program_functions
            SET program_id = (SELECT id FROM programs WHERE program_name = '#{options[:to_program]}'
                              AND functional_area_id = (SELECT id FROM functional_areas
                              WHERE functional_area_name ='#{options[:to_functional_area] || options[:functional_area]}'))
            WHERE program_function_name = '#{key}'
              AND program_id = (SELECT id FROM programs
                                WHERE program_name = '#{options[:program]}'
                                AND functional_area_id = (SELECT id FROM functional_areas
                                                          WHERE functional_area_name ='#{options[:functional_area]}'));
          SQL
          @script << sql.gsub(/\n\s*/, ' ').rstrip
        end

        PF_KEYS = %i[functional_area program seq group url restricted show_in_iframe rename match_group hide_if_const_true hide_if_const_false].freeze
        def change_program_function(key, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
          raise Error, "Cannot change program function #{key} - no changes given" if options.empty? || options.length == 2
          raise Error, "Cannot change program function #{key} - no functional area given" unless options[:functional_area]
          raise Error, "Cannot change program function #{key} - no program given" unless options[:program]
          raise Error, "Cannot change program function #{key} - invalid options" unless options.keys.all? { |o| PF_KEYS.include?(o) }

          check_string!(key, options[:functional_area], options[:program], options[:group], options[:rename], options[:match_group], options[:hide_if_const_true], options[:hide_if_const_false])

          changes = []
          changes << "program_function_sequence = #{options[:seq]}" if options[:seq]
          if options.key?(:group)
            s = options[:group].nil? ? 'group_name = NULL' : "group_name = '#{options[:group]}'"
            changes << s
          end
          group_where = if options[:match_group]
                          " AND group_name = '#{options[:match_group]}'"
                        else
                          ' AND group_name IS NULL'
                        end
          if options.key?(:hide_if_const_true)
            s = options[:hide_if_const_true].nil? ? 'hide_if_const_true = NULL' : "hide_if_const_true = '#{options[:hide_if_const_true]}'"
            changes << s
          end
          if options.key?(:hide_if_const_false)
            s = options[:hide_if_const_false].nil? ? 'hide_if_const_false = NULL' : "hide_if_const_false = '#{options[:hide_if_const_false]}'"
            changes << s
          end
          changes << "url = '#{options[:url]}'" if options[:url]
          changes << "restricted_user_access = #{options[:restricted]}" unless options[:restricted].nil?
          changes << "show_in_iframe = #{options[:show_in_iframe]}" unless options[:show_in_iframe].nil?
          changes << "program_function_name = '#{options[:rename]}'" if options[:rename]
          @script << "UPDATE program_functions SET #{changes.join(', ')} WHERE program_function_name = '#{key}' AND program_id = (SELECT id FROM programs WHERE program_name = '#{options[:program]}' AND functional_area_id = (SELECT id FROM functional_areas WHERE functional_area_name ='#{options[:functional_area]}'))#{group_where};"
        end

        private

        def check_string!(*args)
          args.each do |arg|
            next if arg.nil?

            raise Error, %(Invalid string - "#{arg}" is padded with spaces) if arg.strip != arg
          end
        end
      end

      # DSL for loading the up and down blocks.
      class MigrationDSL < BasicObject
        # The underlying SimpleMigration instance
        attr_reader :migration

        def self.create(webapp, dry_run, &block)
          new(webapp, dry_run, &block).migration
        end

        # Create a new migration class, and instance_exec the block.
        def initialize(webapp, dry_run, &block)
          @migration = SimpleMigration.new(webapp, dry_run: dry_run || false)
          Migrator.migrations << migration
          instance_exec(&block)
        end

        # Defines the migration's down action.
        def down(&block)
          migration.down = block
        end

        # Defines the migration's up action.
        def up(&block)
          migration.up = block
        end
      end

      def self.run(db, directory, target = nil)
        new(db, directory, target).run
      end

      def self.migration(webapp, dry_run: false, &block)
        MigrationDSL.create(webapp, dry_run, &block)
      end

      attr_reader :db, :directory, :target, :files, :applied_migrations, :migration_tuples

      def initialize(db, directory, target = nil)
        @db = db
        setup_table
        @directory = directory
        @target = target
        @files = migration_files
        @applied_migrations = find_applied_migrations
        @migration_tuples = find_migration_tuples
      end

      def run
        migration_tuples.each do |m, f, direction|
          m.apply(db, direction, f)
        end
      end

      # Load the migration file, raising an exception if the file does not define
      # a single migration.
      def load_migration_file(file) # rubocop:disable Metrics/AbcSize
        MUTEX.synchronize do
          n = Migrator.migrations.length
          load(file)
          raise Error, "Migration file #{file.inspect} not containing a single migration detected" unless n + 1 == Migrator.migrations.length

          c = Migrator.migrations.pop

          Object.send(:remove_const, c.name) if c.is_a?(Class) && !c.name.to_s.empty? && Object.const_defined?(c.name)
          c
        end
      end

      # Return the integer migration version based on the filename.
      def migration_version_from_file(filename)
        filename.split('_', 2).first.to_i
      end

      # Returns filenames of all applied migrations
      def find_applied_migrations
        am = db[:menu_migrations].select_order_map(:filename)
        missing_migration_files = am - files.map { |f| File.basename(f).downcase }
        raise(Error, "Applied migration files not in file system: #{missing_migration_files.join(', ')}") unless missing_migration_files.empty?

        am
      end

      # Returns any migration files found in the migrator's directory.
      def migration_files # rubocop:disable Metrics/AbcSize
        files = []
        Dir.new(directory).each do |file|
          next unless MIGRATION_FILE_PATTERN.match(file)
          raise Error, "#{file} does not start with a valid datetime" unless file_date_valid?(file)
          raise Error, "#{file} name is invalid - it must be all lowercase" unless file == file.downcase

          files << File.join(directory, file)
        end
        files.sort_by { |f| MIGRATION_FILE_PATTERN.match(File.basename(f))[1].to_i }
      end

      # Check that the first characters of the filename form a valid date/time
      def file_date_valid?(file)
        dt = file.split('_').first
        return false if dt.length != 12

        begin
          Time.parse(dt)
        rescue StandardError
          return false
        end

        true
      end

      # Returns tuples of migration, filename, and direction
      def find_migration_tuples # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
        up_mts = []
        down_mts = []
        files.each do |path|
          f = File.basename(path)
          fi = f.downcase
          if target
            if migration_version_from_file(f) > target
              down_mts << [load_migration_file(path), f, :down] if applied_migrations.include?(fi)
            elsif !applied_migrations.include?(fi)
              up_mts << [load_migration_file(path), f, :up]
            end
          elsif !applied_migrations.include?(fi)
            up_mts << [load_migration_file(path), f, :up]
          end
        end
        up_mts + down_mts.reverse
      end

      def setup_table
        return if db.table_exists?(:menu_migrations)

        db.instance_exec do
          create_table(:menu_migrations) do
            String :filename, primary_key: true
          end
        end
      end

      def ok_to_run?(direction, target)
        val = db[:menu_migrations].where(filename: target).get(:filename)
        if direction == :up
          val.nil?
        else
          !val.nil?
        end
      end
    end
  end
end
