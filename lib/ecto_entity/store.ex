defmodule EctoEntity.Store do
  def init(config) do
    %{config: config}
  end

  def get_type(store, source) do
    {module, settings} = get_storage(store)
    apply(module, :get_type, [settings, source])
  end

  def put_type(store, definition) do
    {module, settings} = get_storage(store)
    apply(module, :put_type, [settings, definition])
  end

  def list_types(store) do
    {module, settings} = get_storage(store)
    apply(module, :list_types, [settings])
  end

  def migration_status(store, definition) do
    # TODO: Lots of questions-marks
    raise "Not implemented"
  end

  def migrate(store, definition) do
    # TODO: Implement
    raise "Not implemented"
  end

  def remove_all_data(store, definition) do
    # TODO: Implement
    raise "Not implemented"
  end

  def remove_type(store, definition) when is_map(definition) do
    # TODO: Implement
    raise "Not implemented"
  end

  def remove_type(store, source) when is_binary(source) do
    # TODO: Implement
    raise "Not implemented"
  end

  defp get_storage(store) do
    %{config: %{type_storage: %{module: module, settings: settings}}} = store
    {module, settings}
  end
end
