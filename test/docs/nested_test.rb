require "test_helper"

class DocsNestedOperationTest < Minitest::Spec
  Song = Struct.new(:id, :title) do
    def self.find(id)
      return new(1, "Bristol") if id == 1
    end
  end

  #---
  #- nested operations
  #:edit
  class Edit < Trailblazer::Operation
    extend Contract::DSL

    contract do
      property :title
    end

    step Model( Song, :find )
    step Contract::Build()
  end
  #:edit end

    # step Nested( Edit ) #, "policy.default" => self["policy.create"]
  #:update
  class Update < Trailblazer::Operation
    step Nested( Edit )
    # step Nested( Edit )
    # step ->(options, **) { puts options.keys.inspect }
    step Contract::Validate()

    step Contract::Persist( method: :sync )
  end
  #:update end

  # puts Update["pipetree"].inspect(style: :rows)

  #-
  # Edit allows grabbing model and contract
  it do
  #:edit-call
  result = Edit.(id: 1)

  result["model"]            #=> #<Song id=1, title=\"Bristol\">
  result["contract.default"] #=> #<Reform::Form ..>
  #:edit-call end
    result.inspect("model").must_equal %{<Result:true [#<struct DocsNestedOperationTest::Song id=1, title=\"Bristol\">] >}
    result["contract.default"].model.must_equal result["model"]
  end

#- test Edit circuit-level.
it do
  dir, result, _ = Edit.__call__(Edit.instance_variable_get(:@start), {"params" => {id: 1} }, {})
  result["model"].inspect.must_equal %{#<struct DocsNestedOperationTest::Song id=1, title=\"Bristol\">}
end

  #-
  # Update also allows grabbing Edit/model and Edit/contract
  it do
  #:update-call
  result = Update.(id: 1, title: "Call It A Night")

  result["model"]            #=> #<Song id=1 , title=\"Call It A Night\">
  result["contract.default"] #=> #<Reform::Form ..>
  #:update-call end
    result.inspect("model").must_equal %{<Result:true [#<struct DocsNestedOperationTest::Song id=1, title=\"Call It A Night\">] >}
    result["contract.default"].model.must_equal result["model"]
  end

  #-
  # Edit is successful.
  it do
    result = Update.({ id: 1, title: "Miami" }, "current_user" => Module)
    result.inspect("model").must_equal %{<Result:true [#<struct DocsNestedOperationTest::Song id=1, title="Miami">] >}
  end

  # Edit fails
  it do
    Update.(id: 2).inspect("model").must_equal %{<Result:false [nil] >}
  end
end

class NestedInput < Minitest::Spec
  #:input-multiply
  class Multiplier < Trailblazer::Operation
    step ->(options, x:, y:, **) { options["product"] = x*y }
  end
  #:input-multiply end

  #:input-pi
  class MultiplyByPi < Trailblazer::Operation
    step ->(options, **) { options["pi_constant"] = 3.14159 }
    step Nested( Multiplier, input: ->(options, mutable_data:, runtime_data:, **) do

      puts "@@@@@ #{runtime_data.inspect}"

      { "y" => mutable_data["pi_constant"],
        "x" => runtime_data["x"] }
    end )
  end
  #:input-pi end

  it { MultiplyByPi.({}, "x" => 9).inspect("product").must_equal %{<Result:true [28.27431] >} }

  it do
    #:input-result
    result = MultiplyByPi.({}, "x" => 9)
    result["product"] #=> [28.27431]
    #:input-result end
  end
end

class NestedInputCallable < Minitest::Spec
  Multiplier = NestedInput::Multiplier

  #:input-callable
  class MyInput
    def self.call(options, mutable_data:, runtime_data:, **)
      {
        "y" => mutable_data["pi_constant"],
        "x" => runtime_data["x"]
      }
    end
  end
  #:input-callable end

  #:input-callable-op
  class MultiplyByPi < Trailblazer::Operation
    step ->(options, **) { options["pi_constant"] = 3.14159 }
    step Nested( Multiplier, input: MyInput )
  end
  #:input-callable-op end

  it { MultiplyByPi.({}, "x" => 9).inspect("product").must_equal %{<Result:true [28.27431] >} }
end

#---
#- Nested( .., output: )
class NestedOutput < Minitest::Spec
  Edit = DocsNestedOperationTest::Edit

  #:output
  class Update < Trailblazer::Operation
    step Nested( Edit, output: ->(options, mutable_data:, **) do
      {
        "contract.my" => mutable_data["contract.default"],
        "model"       => mutable_data["model"]
      }
    end )
    step Contract::Validate( name: "my" )
    step Contract::Persist( method: :sync, name: "my" )
  end
  #:output end

  it { Update.( id: 1, title: "Call It A Night" ).inspect("model", "contract.default").must_equal %{<Result:true [#<struct DocsNestedOperationTest::Song id=1, title=\"Call It A Night\">, nil] >} }

  it do
    result = Update.( id: 1, title: "Call It A Night" )

    result["model"]            #=> #<Song id=1 , title=\"Call It A Night\">
  end
end

class NestedClassLevelTest < Minitest::Spec
  #:class-level
  class New < Trailblazer::Operation
    step ->(options, **) { options["class"] = true }#, before: "operation.new"
    step ->(options, **) { options["x"] = true }
  end

  class Create < Trailblazer::Operation
    step Nested( New )
    step ->(options, **) { options["y"] = true }
  end
  #:class-level end

  it { Create.().inspect("x", "y").must_equal %{<Result:true [true, true] >} }
  it { Create.(); Create["class"].must_equal nil }
end

#---
# Nested( ->{} )
class NestedWithCallableTest < Minitest::Spec
  Song = Struct.new(:id, :title)

  class Song
    module Contract
      class Create < Reform::Form
        property :title
      end
    end
  end

  User = Struct.new(:is_admin) do
    def admin?
      !! is_admin
    end
  end

  class Create < Trailblazer::Operation
    step Nested( ->(options, current_user:nil, **) { current_user.admin? ? Admin : NeedsModeration })

    class NeedsModeration < Trailblazer::Operation
      step Model( Song, :new )
      step Contract::Build( constant: Song::Contract::Create )
      step Contract::Validate()
      step :notify_moderator!

      def notify_moderator!(options, **)
        #~noti
        options["x"] = true
        #~noti end
      end
    end

    class Admin < Trailblazer::Operation # TODO: test if current_user is passed in.

    end
  end

  let (:admin) { User.new(true) }
  let (:anonymous) { User.new(false) }

  it { Create.({}, "current_user" => anonymous).inspect("x").must_equal %{<Result:true [true] >} }
  it { Create.({}, "current_user" => admin)    .inspect("x").must_equal %{<Result:true [nil] >} }

  #---
  #:method
  class Update < Trailblazer::Operation
    step Nested( :build! )

    def build!(options, current_user:nil, **)
        current_user.admin? ? Create::Admin : Create::NeedsModeration
    end
  end
  #:method end

  it { Update.({}, "current_user" => anonymous).inspect("x").must_equal %{<Result:true [true] >} }
  it { Update.({}, "current_user" => admin)    .inspect("x").must_equal %{<Result:true [nil] >} }

  #---
  #:callable-builder
  class MyBuilder
    extend Uber::Callable

    def self.call(options, current_user:nil, **)
      current_user.admin? ? Create::Admin : Create::NeedsModeration
    end
  end
  #:callable-builder end

  #:callable
  class Delete < Trailblazer::Operation
    step Nested( MyBuilder )
    # ..
  end
  #:callable end

  it { Delete.({}, "current_user" => anonymous).inspect("x").must_equal %{<Result:true [true] >} }
  it { Delete.({}, "current_user" => admin)    .inspect("x").must_equal %{<Result:true [nil] >} }
end

# builder: Nested + deviate to left if nil / skip_track if true

#---
# automatic :name
class NestedNameTest < Minitest::Spec
  class Create < Trailblazer::Operation
    class Present < Trailblazer::Operation
      # ...
    end

    step Nested( Present )
    # ...
  end

  it { Create["pipetree"].inspect.must_equal %{[>operation.new,>Nested(NestedNameTest::Create::Present)]} }
end
