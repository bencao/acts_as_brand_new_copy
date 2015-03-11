# acts_as_brand_new_copy

[![Gem Version](https://badge.fury.io/rb/acts_as_brand_new_copy.png)](http://badge.fury.io/rb/acts_as_brand_new_copy)
[![Build Status](https://travis-ci.org/bencao/acts_as_brand_new_copy.png)](https://travis-ci.org/bencao/acts_as_brand_new_copy)
[![Code Climate](https://codeclimate.com/github/bencao/acts_as_brand_new_copy/badges/gpa.svg)](https://codeclimate.com/github/bencao/acts_as_brand_new_copy)
[![Test Coverage](https://codeclimate.com/github/bencao/acts_as_brand_new_copy/badges/coverage.svg)](https://codeclimate.com/github/bencao/acts_as_brand_new_copy)

Copy an active record with its associated records are not easy.

For example, if we have defined following classes:

```ruby
class Grade < ActiveRecord::Base
  has_and_belongs_to_many :teachers, :join_table => ::GradeTeacherAssignment.table_name
  has_and_belongs_to_many :students, :join_table => ::GradeStudentAssignment.table_name
end

class Teacher < ActiveRecord::Base
  has_many :student_teacher_assignments
  has_many :students,
    :through => :student_teacher_assignments,
    :source  => :student
end

class Student < ActiveRecord::Base
  has_many :student_teacher_assignments
  has_many :teachers,
    :through => :student_teacher_assignments,
    :source  => :teacher
  has_many :scores
end

class Score < ActiveRecord::Base
  belongs_to :student
end
```

Can you copy a grade with its teachers and students to another grade in a few lines of code, keeping the relationships between teachers and students?
To me, it's no, consequently acts_as_brand_new_copy was born.

## Usage

### copy an active record with its associations

```ruby
# copy student itself, return the id for copied student
copy_id = @student.brand_new_copy

# copy student with their scores
copy_id = @student.brand_new_copy({:associations => [:scores]})

# copy the whole grade and all the relationships between grade to students, teachers to students
# NOTE here shows the convenience bought by this gem, we've ensured that a same student won't be copied twice!
copy_id = @grade.brand_new_copy({:associations => [{:teachers => [:students]}, :students]})
```

### i'd like to do some modifications to records during copy process

Don't worry, we've already supported that!

```
# prefix student name with a 'Copy Of ' during copy
# a callback defined as a class method is needed
Student.class_eval do
  def self.update_name_when_copy(hash_origin, hash_copy, full_context)
    hash_copy['name'] = 'Copy of ' + hash_origin['name']
    true
  end
end
copy_id = @student.brand_new_copy({:callbacks => [:update_name_when_copy]})

# prefix grade, students, teachers name with 'Copy of ', and reset students score to nil during copy
[Grade, Teacher, Student].each do |klass|
  klass.class_eval do
    def self.update_name_when_copy(hash_origin, hash_copy, full_context)
      hash_copy['name'] = 'Copy Of ' + hash_origin['name']
      true
    end
  end
end

Score.class_eval do
  def self.reset_value_when_copy(hash_origin, hash_copy, full_context)
    hash_copy['value'] = nil
    true
  end
end
copy_id = @grade.brand_new_copy({
  :associations => [{:teachers => [:students]}, {:students => [:scores]}],
  :callbacks => [
    :update_name_when_copy,
    {:teachers => [:update_name_when_copy]},
    {:students => [:update_name_when_copy, {:scores => [:reset_value_when_copy]}]}
  ]
})
```

## Installation

Add this line to your application's Gemfile:

    gem 'acts_as_brand_new_copy'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install acts_as_brand_new_copy

## Current Limitation
- do not support has_many_and_belongs_to_many associations when join table class has a strange table_name(I mean, table_name not in [Class.name.underscore, Class.name.underscore.pluralize])

## Contribute

You're highly welcome to improve this gem.

### Checkout source code to local
say you git clone the source code to /tmp/acts_as_brand_new_copy

### Install dev bundle
```bash
$ cd /tmp/acts_as_brand_new_copy
$ bundle install
```

### Do some changes
```bash
$ vi lib/acts_as_brand_new_copy.rb
```

### Run test
```bash
$ bundle exec rspec spec
```
