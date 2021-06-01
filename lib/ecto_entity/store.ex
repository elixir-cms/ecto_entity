defmodule EctoEntity.Store do
  defstruct config: nil

  defmodule Error do
    defexception [:message]
  end

  @type config :: %{
          type_storage: %{
            module: atom(),
            settings: any()
          },
          repo: %{
            module: atom(),
            dynamic: true | false
          }
        }

  @type t :: %__MODULE__{
          config: config()
        }

  @spec init(config :: config) :: t()
  def init(config) when is_map(config) do
    config =
      config
      |> validate_config!()
      |> config_defaults()

    %__MODULE__{config: config}
  end

  @spec init(config :: keyword) :: t()
  def init(config) when is_list(config) do
    if not Keyword.keyword?(config) do
      raise Error, message: "Expected map or keyword, got list."
    end

    config
    |> Map.new()
    |> init()
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

  defp validate_config!(config) do
    %{
      type_storage: %{
        module: _,
        settings: _
      },
      repo: %{
        module: _
      }
    } = config

    config
  end

  @config_defaults %{
    [:repo, :dynamic] => false
  }
  defp config_defaults(config) do
    Enum.reduce(@config_defaults, config, fn {path, default_value}, config ->
      case get_in(config, path) do
        nil -> put_in(config, path, default_value)
        _ -> config
      end
    end)
  end
end
