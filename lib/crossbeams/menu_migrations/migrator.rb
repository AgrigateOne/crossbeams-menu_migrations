# frozen_string_literal: true

module Crossbeams
  module MenuMigrations
    # Apply a migration
    class Migrator
      # NEED:
      # - db connection
      # - path for migrations
      # - menu_migrations table
      # - up
      # - down
      # - Rake
      # - DSL
      # - Maybe a task to re-run a particular migration (there are no dependencies)
      #
      #
      # up do
      #   add_functional_area 'Masterfiles', [rmd_menu: false]
      #   add_program 'Fruit', functional_area: 'Masterfiles', seq: 1, webapp: 'Nspack'
      #   add_program_function 'Cultivars', functional_area: 'Masterfiles', program: 'Fruit', [group: 'Commod'], url: '/list/cult', seq: 1, [restricted: true], [show_in_iframe: false]
      # end
      #
      # down do
      #   drop_functional_area 'Masterfiles' # =>> CASCADES to drop prog & pf & any prog/users
      #   drop_program 'Fruit', functional_area: 'Masterfiles' # =>> CASCADES to drop prog funcs & any prog/users
      #   drop_program_function 'Cultivars', functional_area: 'Masterfiles', program: 'Fruit'
      # end
      #
      #   change_functional_area 'Masterfiles', [rmd_menu: false], rename: 'Master Files'
      #   change_program 'Fruit', functional_area: 'Masterfiles', [seq: 2], rename: 'Fruits'
      #   change_program_function 'Cultivars', functional_area: 'Masterfiles', program: 'Fruit', [group: 'Commod'], [url: '/list/cult'], [seq: 1], [restricted: true], [show_in_iframe: false], rename: 'Variety'
      def self.run(db, path, version)
        new(db, path, version).run
      end

      attr_reader :db, :path, :version

      def initialize(db, path, version)
        @db = db
        @path = path
        @version = version
      end

      def run
        setup_table
        # build table of filenames, sorted
        direction = :down
        direction = :up if version.nil? # OR newer than in db...

        p "Running for direction #{direction}"
        # return unless ok_to_run?(direction, version)
        #
        # File.read(file)
        # readfile(s)
        # setup table
        # run up/down
      end

      def setup_table
        return if db.table_exists?(:menu_migrations)

        db.instance_exec do
          create_table(:menu_migrations) do
            primary_key :filename, type: :String
          end
        end
      end

      def ok_to_run?(direction, version)
        val = db[:menu_migrations].where(filename: version).get(:filename)
        if direction == :up
          val.nil?
        else
          !val.nil?
        end
      end
    end
  end
end
