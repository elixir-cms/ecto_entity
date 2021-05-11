defmodule EctoEntity.Entity do
  alias EctoEntity.Type
  import Ecto.Query, only: [from: 1]

  defimpl Ecto.Queryable, for: Type do
    def to_query(%Type{source: source}) do
      from(source)
    end
  end
end
