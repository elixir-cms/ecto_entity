defmodule EctoEntity.Entity do
  alias EctoEntity.Type
  import Ecto.Query, only: [from: 1]

  defimpl Ecto.Queryable, for: Type do
    def to_query(%Type{source: source}) do
      from(source)
    end
  end

  @doc """
  Turn a raw map from the database into a map typed according to the definition
  in the way that Ecto usually does it with schemas.
  """
  def load(%Type{ephemeral: %{store: store}} = definition, data) do
    # Based off of Ecto.Repo.Schema.load/3
    %{config: %{repo: %{module: repo}}} = store
    loader = &Ecto.Type.adapter_load(repo.__adapter__, &1, &2)

    Enum.reduce(definition.fields, %{}, fn {field, field_opts}, acc ->
      %{field_type: type} = field_opts

      case Map.fetch(data, field) do
        {:ok, value} -> Map.put(acc, field, load!(definition, field, type, value, loader))
        :error -> acc
      end
    end)
  end

  defp load!(definition, field, type, value, loader) do
    # Types are known atom names from ecto
    type = String.to_existing_atom(type)

    case loader.(type, value) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "cannot load `#{inspect(value)}` as type #{inspect(type)} " <>
                "for field `#{field}`#{definition.source}"
    end
  end
end
