defmodule EctoEntity.Store do
  alias EctoEntity.Type

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
            dynamic: pid() | nil
          }
        }

  @type t :: %__MODULE__{
          config: config()
        }

  alias EctoEntity.Store

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

  # TODO: Implement list, get create, update, delete
  def list(%Type{ephemeral: %{store: store}} = definition) when not is_nil(store) do
    list(store, definition)
  end

  def list(%Store{} = store, %Type{} = definition) do
    %{config: %{repo: %{module: repo_module, dynamic: dynamic}}} = store

    if not is_nil(dynamic) do
      repo_module.put_dynamic_repo(dynamic)
    end

    case Ecto.Adapter.SQL.query(repo_module, "select * from #{definition.source}", []) do
      {:ok, result} ->
        result_to_items(repo_module, result)

      # TODO: Check how Repo.all handles errors
      {:error, _} = err ->
        err
    end
  end

  def get_type(store, source) do
    {module, settings} = get_storage(store)

    case apply(module, :get_type, [settings, source]) do
      {:ok, definition} ->
        definition = set_type_store(definition, store)
        {:ok, definition}

      {:error, _} = err ->
        err
    end
  end

  def put_type(store, definition) do
    {module, settings} = get_storage(store)
    apply(module, :put_type, [settings, definition])
  end

  def set_type_store(%{ephemeral: ephemeral} = definition, store) do
    %{definition | ephemeral: Map.put(ephemeral, :store, store)}
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

  defp result_to_items(repo_module, result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      Enum.zip(columns, row)
      |> Map.new()

      # TODO: Map according to repo/adaptor
    end)
  end
end