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

  # TODO: Implement list, get, create, update, delete
  def list(%Type{ephemeral: %{store: store}} = definition) when not is_nil(store) do
    repo_module = set_dynamic(store)

    source = cleanse_source(definition)

    case Ecto.Adapters.SQL.query(repo_module, "select * from #{source}", []) do
      {:ok, result} ->
        result_to_items(definition, result)

      # TODO: Check how Repo.all handles errors
      {:error, _} = err ->
        err
    end
  end

  def list(%Store{} = store, %Type{} = definition) do
    definition
    |> set_type_store(store)
    |> list()
  end

  def insert(%Type{ephemeral: %{store: store}} = definition, entity) when not is_nil(store) do
    repo_module = set_dynamic(store)

    source = cleanse_source(definition)
    # TODO: Restrict character set for field names, replace anything not very valid
    columns =
      entity
      |> Map.keys()
      |> Enum.map(&cleanse_field_name/1)
      |> Enum.join(", ")

    values = Map.values(entity)

    value_holders =
      values
      |> Enum.with_index()
      |> Enum.map(fn {_value, index} ->
        "$#{index + 1}"
      end)
      |> Enum.join(", ")

    case Ecto.Adapters.SQL.query(
           repo_module,
           "insert into #{source} (#{columns}) values (#{value_holders})",
           values
         ) do
      {:ok, %{num_rows: count}} ->
        {:ok, count}

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

  defp result_to_items(definition, result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      item =
        columns
        |> Enum.zip(row)

      EctoEntity.Entity.load(definition, item)
    end)
  end

  defp set_dynamic(store) do
    %{config: %{repo: %{module: repo_module, dynamic: dynamic}}} = store

    if not is_nil(dynamic) and dynamic do
      repo_module.put_dynamic_repo(dynamic)
    end

    repo_module
  end

  defp cleanse_source(%{source: source}) do
    # Strip out all expect A-Z a-z 0-9 - _
    Regex.replace(~r/[^A-Za-z0-9-_]/, source, "")
  end

  defp cleanse_field_name(field) do
    # Strip out all expect A-Z a-z 0-9 - _
    # SQL does allow pretty much anything, we don't.
    Regex.replace(~r/[^A-Za-z0-9-_]/, field, "")
  end
end
