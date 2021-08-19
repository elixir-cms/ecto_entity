defmodule MigrationsAgent do
  use Agent

  def start_link(versions) do
    Agent.start_link(fn -> versions end, name: __MODULE__)
  end

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def up(version, opts) do
    Agent.update(__MODULE__, &[{version, opts[:prefix]} | &1])
  end

  def down(version, opts) do
    Agent.update(__MODULE__, &List.delete(&1, {version, opts[:prefix]}))
  end
end

defmodule EctoSQL.TestServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl true
  def init(opts) do
    {:ok, opts}
  end
end

defmodule EctoSQL.TestAdapter do
  defmodule Connection do
    @behaviour Ecto.Adapters.SQL.Connection

    ## Module and Options

    @impl true
    def child_spec(opts) do
      EctoSQL.TestServer.child_spec(opts)
    end

    @impl true
    def to_constraints(err, opts) do
      send(self(), {:to_constraints, err, opts})
      []
    end

    ## Query

    @impl true
    def prepare_execute(conn, name, sql, params, opts) do
      send(self(), {:prepare_execute, conn, name, sql, params, opts})
      {:ok, sql, :fine}
    end

    @impl true
    def query(conn, sql, params, opts) do
      send(self(), {:query, conn, sql, params, opts})

      case String.downcase(sql) do
        "insert " <> _ -> {:ok, %{num_rows: 1}}
        "update" <> _ -> {:ok, %{num_rows: 1}}
        "delete" <> _ -> {:ok, %{num_rows: 1}}
        _ -> {:ok, %{columns: [], rows: []}}
      end
    end

    @impl true
    def execute(conn, query, params, opts) do
      send(self(), {:execute, conn, query, params, opts})
      {:ok, %{columns: [], rows: []}}
    end

    @impl true
    def stream(conn, sql, params, opts) do
      send(self(), {:stream, conn, sql, params, opts})
      Stream.map([1, 2, 3], fn i -> i end)
    end

    @impl true
    def all(query, as_prefix \\ []) do
      send(self(), {:all, query, as_prefix})
      query
    end

    @impl true
    def update_all(query, prefix \\ nil) do
      send(self(), {:update_all, query, prefix})
      query
    end

    @impl true
    def delete_all(query) do
      send(self(), {:delete_all, query})
      query
    end

    @impl true
    def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
      send(self(), {:insert, prefix, table, header, rows, on_conflict, returning, placeholders})
      "insert"
    end

    @impl true
    def update(prefix, table, fields, filters, returning) do
      send(self(), {:update, prefix, table, fields, filters, returning})
      "update"
    end

    @impl true
    def delete(prefix, table, filters, returning) do
      send(self(), {:delete, prefix, table, filters, returning})
      "delete"
    end

    @impl true
    def ddl_logs(result) do
      send(self(), {:ddl_logs, result})
      raise "not implemented"
    end

    @impl true
    def execute_ddl(command) do
      send(self(), {:execute_ddl, command})
      raise "not implemented"
    end

    @impl true
    def explain_query(connection, query, params, opts) do
      send(self(), {:explain_query, connection, query, params, opts})
      raise "not implemented"
    end

    @impl true
    def table_exists_query(table) do
      send(self(), {:table_exists_query, table})
      raise "not implemented"
    end
  end

  use Ecto.Adapters.SQL, driver: :test
  #  @behaviour Ecto.Adapter
  #  @behaviour Ecto.Adapter.Queryable
  #  @behaviour Ecto.Adapter.Schema
  #  @behaviour Ecto.Adapter.Transaction
  #  @behaviour Ecto.Adapter.Migration

  defmacro __before_compile__(_opts), do: :ok
  def ensure_all_started(_, _), do: {:ok, []}

  def checked_out?(_), do: raise("not implemented")

  ## Types

  def loaders(_primitive, type), do: [type]
  def dumpers(_primitive, type), do: [type]
  def autogenerate(_), do: nil

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  # Migration emulation

  def execute(_, _, {:nocache, {:all, %{from: %{source: {"schema_migrations", _}}}}}, _, opts) do
    true = opts[:schema_migration]
    versions = MigrationsAgent.get()
    {length(versions), Enum.map(versions, &[elem(&1, 0)])}
  end

  def execute(
        _,
        _meta,
        {:nocache, {:delete_all, %{from: %{source: {"schema_migrations", _}}}}},
        [version],
        opts
      ) do
    true = opts[:schema_migration]
    MigrationsAgent.down(version, opts)
    {1, nil}
  end

  def insert(_, %{source: "schema_migrations"}, val, _, _, opts) do
    true = opts[:schema_migration]
    version = Keyword.fetch!(val, :version)
    MigrationsAgent.up(version, opts)
    {:ok, []}
  end

  ## Migrations

  def lock_for_migrations(mod, opts, fun) do
    send(test_process(), {:lock_for_migrations, mod, fun, opts})
    fun.()
  end

  def execute_ddl(_, command, _) do
    Process.put(:last_command, command)
    {:ok, []}
  end

  def supports_ddl_transaction? do
    get_config(:supports_ddl_transaction?, false)
  end

  defp test_process do
    get_config(:test_process, self())
  end

  defp get_config(name, default) do
    :ecto_sql
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(name, default)
  end
end

defmodule EctoSQL.TestRepo do
  use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter

  def default_options(_operation) do
    Process.get(:repo_default_options, [])
  end
end

defmodule EctoSQL.MigrationTestRepo do
  use Ecto.Repo, otp_app: :ecto_sql, adapter: EctoSQL.TestAdapter
end

EctoSQL.TestRepo.start_link()
EctoSQL.TestRepo.start_link(name: :tenant_db)
EctoSQL.MigrationTestRepo.start_link()
