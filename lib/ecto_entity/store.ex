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

  def list(%Type{ephemeral: %{store: store}} = definition) when not is_nil(store) do
    repo = set_dynamic(store)

    source = cleanse_source(definition)

    case Ecto.Adapters.SQL.query(repo, "select * from #{source}", []) do
      {:ok, result} ->
        result_to_items(definition, result)

      {:error, _} ->
        # Would be nice to add query info and stuff to this error
        raise Ecto.QueryError
    end
  end

  def list(%Store{} = store, %Type{} = definition) do
    definition
    |> set_type_store(store)
    |> list()
  end


  def insert(%Type{ephemeral: %{store: store}} = definition, entity) when not is_nil(store) do
    repo = set_dynamic(store)
    new_id = new_id_for_type(definition)

    source = cleanse_source(definition)

    columns =
      entity
      |> Enum.sort()
      |> Enum.map(fn {key, _value} ->
        cleanse_field_name(key)
      end)

    columns =
      if new_id do
        ["id" | columns]
      else
        columns
      end

    values =
      entity
      |> Enum.sort()
      |> Enum.map(fn {_key, value} ->
        value
      end)

    values =
      if new_id do
        [new_id | values]
      else
        values
      end

      connection_module = store.config.repo.module.__adapter__()
                          |> Module.concat(Connection)

      prefix = nil
      sql = connection_module.insert(prefix, source, columns, [values], {:raise, nil, []}, [], [])

      case Ecto.Adapters.SQL.query(
           repo,
           #"insert into #{source} (#{columns}) values (#{value_holders}) returning *",
           sql,
           values
         ) do
      {:ok, _result} ->
        # This could be done with RETURNING *, but that doesn't work in MySQL
        #[item] = result_to_items(definition, result)
        {:ok, nil}

      {:error, _} = err ->
        err
    end
  end

  def update(%Type{ephemeral: %{store: store}} = definition, %{"id" => id} = _entity, updates_kv)
      when not is_nil(store) do
    updates = Enum.into(updates_kv, %{})
    repo = set_dynamic(store)

    source = cleanse_source(definition)

    {changes, last_index} =
      updates
      |> Enum.sort()
      |> Enum.map(fn {key, _value} ->
        key
      end)
      |> Enum.reduce({[], 1}, fn field, {changes, index} ->
        field =
          case field do
            field when is_atom(field) ->
              Atom.to_string(field)

            field when is_binary(field) ->
              field
          end

        field = cleanse_field_name(field)
        change = "#{field}=$#{index}"
        {[change | changes], index + 1}
      end)

    changes =
      changes
      |> Enum.reverse()
      |> Enum.join(", ")

    values =
      updates
      |> Enum.sort()
      |> Enum.map(fn {_key, value} ->
        value
      end)

    values = values ++ [id]



    case Ecto.Adapters.SQL.query(
           repo,
           "update #{source} set #{changes} where id=$#{last_index} returning *",
           values
         ) do
      {:ok, result} ->
        [item] = result_to_items(definition, result)
        {:ok, item}

      {:error, _} = err ->
        err
    end
  end

  def delete(%Type{ephemeral: %{store: store}} = definition, %{"id" => id} = _entity)
      when not is_nil(store) do
    repo = set_dynamic(store)
    source = cleanse_source(definition)

    case Ecto.Adapters.SQL.query(
           repo,
           # Note: returning * provides affected row count in SQLite
           "delete from #{source} where id=$1 returning *",
           [id]
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

  def put_type(store, %{source: source} = definition) do
    {module, settings} = get_storage(store)

    case apply(module, :put_type, [settings, definition]) do
      :ok ->
        get_type(store, source)

      err ->
        err
    end
  end

  def remove_type(store, source) do
    {module, settings} = get_storage(store)
    apply(module, :remove_type, [settings, source])
  end

  def set_type_store(%{ephemeral: ephemeral} = definition, store) do
    %{definition | ephemeral: Map.put(ephemeral, :store, store)}
  end

  def list_types(store) do
    {module, settings} = get_storage(store)
    apply(module, :list_types, [settings])
  end

  def migration_status(_store, _definition) do
    # TODO: Lots of questions-marks
    raise "Not implemented"
  end

  def migrate(_store, _definition) do
    # TODO: Implement
    raise "Not implemented"
  end

  def remove_all_data(%Type{ephemeral: %{store: store}} = definition) when not is_nil(store) do
    repo = set_dynamic(store)
    source = cleanse_source(definition)

    case Ecto.Adapters.SQL.query(
           repo,
           "delete from #{source} returning *",
           []
         ) do
      {:ok, %{num_rows: count}} ->
        {:ok, count}

      {:error, _} = err ->
        err
    end
  end

  def drop_table(%Type{ephemeral: %{store: store}} = definition) when not is_nil(store) do
    repo = set_dynamic(store)
    source = cleanse_source(definition)

    case Ecto.Adapters.SQL.query(
           repo,
           "drop table #{source}",
           []
         ) do
      {:ok, _} ->
        :ok

      {:error, _} = err ->
        err
    end
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
      dynamic
    else
      repo_module
    end
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

  defp new_id_for_type(definition) do
    # TODO: Currently assumes single primary key
    {_field_name, field_options} =
      Enum.find(definition.fields, fn {_key, field_opts} ->
        get_in(field_opts, [:persistence_options, :primary_key]) || false
      end)

    case field_options.storage_type do
      "id" -> nil
      "string" -> UUID.uuid1()
    end
  end
end
