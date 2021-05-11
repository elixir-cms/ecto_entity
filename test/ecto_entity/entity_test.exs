defmodule EctoEntity.EntityTest do
  use ExUnit.Case, async: true

  # doctest EctoEntity.Entity

  alias EctoEntity.Type
  import Ecto.Query, only: [from: 1]

  @label "Post"
  @source "posts"
  @singular "post"
  @plural "posts"

  test "query from type via protocol" do
    type = Type.new(@source, @label, @singular, @plural)
    assert %Ecto.Query{} = from(type)
  end
end
