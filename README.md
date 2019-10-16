# Crossbeams::MenuMigrations

Menu migrator for Crossbeams framework projects.

Migration files must be named with timestamp prefixes (`YYYYMMDDHHMM_`) and stored in the same directory.o

Each file uses a Ruby DSL to add/drop/change parts of the menu structure.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'crossbeams-menu_migrations'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install crossbeams-menu_migrations

## Usage

### Writing migration files.

Migration files call `Crossbeams::MenuMigrations::Migrator.migration` to do the migration.
The `migration` method, besides a block, takes two parameters - the webapp and a boolean for dry runs which defaults to `false`.
Pass in `true` to get the migration to print the SQL to be run without actually running it.

There are nine migration methods:

* `add_functional_area` - creates a `functional_areas` record.
* `add_program` - creates a `programs` record and a `programs_webapps` record.
* `add_program_function` - creates a `program_functions` record.
* `drop_functional_area` - deletes a `functional_areas` record - and all is dependents.
* `drop_program` - deletes a `programs` record - and all is dependents.
* `drop_program_function` - deletes a `program_functions` record - and all is dependents.
* `change_functional_area` - changes aspects of a `functional_areas` record.
* `change_program` - changes aspects of a `programs` record.
* `change_program_function` - changes aspects of a `program_functions` record.

```ruby
Crossbeams::MenuMigrations::Migrator.migration('Nspack') do
  up do
    add_functional_area 'Dummy'
    add_program 'This', functional_area: 'Dummy'
    add_program_function 'Thing', functional_area: 'Dummy', program: 'This', url: '/a/path'
  end

  down do
    # drop_program_function 'Thing', functional_area: 'Dummy', program: 'This'
    # drop_program 'This', functional_area: 'Dummy'
    drop_functional_area 'Dummy'
  end
end

Crossbeams::MenuMigrations::Migrator.migration('Nspack') do
  up do
    change_functional_area 'Dummy', rename: 'Fred'
    change_program 'This', functional_area: 'Fred', seq: 33, rename: 'Other'
    change_program_function 'Thing', functional_area: 'Fred', program: 'Other', seq: 22, url: '/another/path/here', group: 'Together',  rename: 'Object'
  end

  down do
    change_program_function 'Object', functional_area: 'Fred', program: 'Other', seq: 1, url: '/a/path', group: nil,  rename: 'Thing'
    change_functional_area 'Fred', rename: 'Dummy'
    change_program 'Other', functional_area: 'Dummy', seq: 33, rename: 'This'
  end
end
```

### Running migrations.

```ruby
# To run all outstanding migrations:
Crossbeams::MenuMigrations::Migrator.run(db, 'db/menu')

# To run either outstanding igrations up to `version`
# OR to rollback applied migrations down to (and excluding) `version`.
Crossbeams::MenuMigrations::Migrator.run(db, 'db/menu', args[:version].to_i)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/crossbeams-menu_migrations.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
