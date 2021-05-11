defmodule EctoEntity.Type.Persist do
  alias EctoEntity.Type

  @spec to_persistable(type :: Type.t() | Type.map_t()) :: map()
  def to_persistable(type) do
    Map.drop(type, [:__struct__, :ephemeral])
  end

  @spec from_persistable!(stringly_type :: map) :: Type.t()
  def from_persistable!(stringly_type) do
    base_fields = Type.__struct__() |> Map.keys()

    # TODO: Convert string keys that should be atom to atoms, leave others alone
    Enum.reduce(stringly_type, %{}, fn {key, value}, Type.t() ->
      try do
        field = String.to_existing_atom(key)

        if field in base_fields do
          case field do
            :fields ->
              val = fields_from_map!(value)
              Map.put(t, field, val)

            _ ->
              Map.put(t, field, value)
          end
        else
          raise Error, "Field does not exist in Type data structure: #{field}"
        end
      catch
        _ -> raise Error, "Field does not map to a known atom, cannot be a field in Type"
      end
    end)
  end
end
