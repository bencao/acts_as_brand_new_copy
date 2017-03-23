require 'spec_helper'
require 'acts_as_brand_new_copy'

class Schema < ActiveRecord::Migration
  def change
    create_table :grades do |t|
      t.string :name
    end

    create_table :teachers do |t|
      t.string :name
    end

    create_table :students do |t|
      t.string :name
    end

    create_table :scores do |t|
      t.string :value
      t.references :student
    end

    create_table :grade_teacher_assignments, :id => false do |t|
      t.references :grade
      t.references :teacher
    end

    create_table :grade_student_assignments, :id => false do |t|
      t.references :grade
      t.references :student
    end

    create_table :student_teacher_assignments do |t|
      t.references :teacher
      t.references :student
    end
  end

end

Schema.new.change

class StudentTeacherAssignment < ActiveRecord::Base
  belongs_to :teacher
  belongs_to :student
end

class GradeTeacherAssignment < ActiveRecord::Base
  belongs_to :grade
  belongs_to :teacher
end

class GradeStudentAssignment < ActiveRecord::Base
  belongs_to :grade
  belongs_to :student
end

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


FactoryGirl.define do
  factory :grade do
    sequence(:name) {|n| "Grade #{n}"}
  end

  factory :teacher do
    sequence(:name) {|n| "Teacher #{n}"}
  end

  factory :student do
    sequence(:name) {|n| "Student #{n}"}

    trait :with_scores do
      after(:create) do |student, _|
        FactoryGirl.create(:score, {:student => student, :value => "70"})
        FactoryGirl.create(:score, {:student => student, :value => "80"})
      end
    end
  end

  factory :score do
  end
end

describe ActsAsBrandNewCopy do
  context "copy associations" do
    it "should copy self" do
      @student = create(:student)
      copy_id = @student.brand_new_copy
      copied_student = Student.find copy_id
      copied_student.name.should == @student.name
      copied_student.id.should_not == @student.id
    end

    it "should copy belongs_to associations" do
      # NOTE although brand new copy support belongs_to association copy
      # it's not common in real world that we need to copy belongs_to association
      # You should avoid doing that or you should check your design
      @student = create(:student, :with_scores)
      @score1 = @student.scores.first

      copy_id = @score1.brand_new_copy({:associations => [:student]})

      copied_score = Score.find(copy_id)

      copied_score.student.name.should == @student.name
      copied_score.student.id.should_not == @student.id
    end

    it "should copy has_many associations" do
      @student = create(:student, :with_scores)
      @score1, @score2 = @student.scores

      copy_id = @student.brand_new_copy({:associations => [:scores]})

      copied_student = Student.find copy_id
      copied_student.scores.size.should == @student.scores.size
      copied_student.scores.map(&:value).sort.should == @student.scores.map(&:value).sort
      (copied_student.scores.map(&:id) - @student.scores.map(&:id)).size.should == 2
    end

    it "should copy has_many through associations" do
      @teacher = create(:teacher)
      @student1, @student2 = create_list(:student, 2)
      @teacher.students << @student1
      @teacher.students << @student2

      copy_id = @teacher.brand_new_copy({:associations => [:students]})
      copied_teacher = Teacher.find copy_id
      copied_teacher.students.size.should == @teacher.students.size
      copied_teacher.students.map(&:name).sort.should == @teacher.students.map(&:name).sort
      (copied_teacher.students.map(&:id) - @teacher.students.map(&:id)).size.should == 2
    end

    it "should copy has_and_belongs_to_many associations" do
      @grade = create(:grade)
      @student1, @student2 = create_list(:student, 2)
      @grade.students << @student1
      @grade.students << @student2

      copy_id = @grade.brand_new_copy({:associations => [:students]})
      copied_grade = Grade.find copy_id
      copied_grade.students.size.should == @grade.students.size
      copied_grade.students.map(&:name).sort.should == @grade.students.map(&:name).sort
      (copied_grade.students.map(&:id) - @grade.students.map(&:id)).size.should == 2
    end

    it "should not copy a same association instance twice" do
      @grade = create(:grade)
      @teacher = create(:teacher)
      @grade.teachers << @teacher
      @student1, @student2 = create_list(:student, 2)
      @grade.students << @student1
      @grade.students << @student2
      @teacher.students << @student1
      @teacher.students << @student2

      copy_id = @grade.brand_new_copy({:associations => [{:teachers => [:students]}, :students]})
      copied_grade = Grade.find copy_id
      copied_grade.students.size.should == @grade.students.size
      (copied_grade.students.map(&:id) - @grade.students.map(&:id)).size.should == 2
      copied_grade.teachers.size.should == @grade.teachers.size
      copied_grade.students.map(&:name).sort.should == @grade.students.map(&:name).sort
      Student.where(:name => @student1.name).size.should == 2
      Student.where(:name => @student2.name).size.should == 2
      copied_grade.teachers.first.students.size.should == @teacher.students.size
      copied_grade.teachers.first.students.map(&:name).sort.should == @teacher.students.map(&:name).sort
    end

  end

  context "callbacks" do
    [Grade, Teacher, Student].each do |klass|
      klass.class_eval do
        def self.update_name_when_copy(hash_origin, hash_copy, _)
          hash_copy['name'] = copy_of_name(hash_origin['name'])
          true
        end

        def self.copy_of_name(name)
          'Copy of ' + name
        end
      end
    end

    Score.class_eval do
      def self.reset_value_when_copy(hash_origin, hash_copy, _)
        hash_copy['value'] = nil
        true
      end
    end

    it "should invoke callbacks on self" do
      @student = create(:student)
      copy_id = @student.brand_new_copy({:callbacks => [:update_name_when_copy]})
      copied_student = Student.find copy_id
      copied_student.name.should == Student.copy_of_name(@student.name)
    end

    it "should invoke callbacks on associations" do
      @grade = create(:grade)
      @teacher = create(:teacher)
      @grade.teachers << @teacher
      @student1, @student2 = create_list(:student, 2, :with_scores)
      @grade.students << @student1
      @grade.students << @student2
      @teacher.students << @student1
      @teacher.students << @student2

      copy_id = @grade.brand_new_copy({
        :associations => [{:teachers => [:students]}, {:students => [:scores]}],
        :callbacks => [
          :update_name_when_copy,
          {:teachers => [:update_name_when_copy]},
          {:students => [:update_name_when_copy, {:scores => [:reset_value_when_copy]}]}
        ]
      })
      copied_grade = Grade.find copy_id
      copied_grade.name.should == Grade.copy_of_name(@grade.name)
      copied_grade.teachers.first.name.should == Teacher.copy_of_name(@teacher.name)
      copied_grade.students.map(&:name).sort.should == [
        Student.copy_of_name(@student1.name),
        Student.copy_of_name(@student2.name)
      ].sort
      copied_grade.students.map(&:scores).flatten.map(&:value).compact.should be_blank
    end

  end

end
