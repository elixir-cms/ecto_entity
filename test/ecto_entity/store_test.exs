defmodule EctoEntity.StoreTest do
  use ExUnit.Case, async: true

  alias EctoEntity.Store
  alias EctoEntity.Store.Storage.Error
  import EctoEntity.Store.Storage, only: [error: 2]
  alias EctoEntity.Type

  @settings %{foo: 1, bar: 2}

  defmodule StorageTest do
    @behaviour EctoEntity.Store.Storage
    @settings %{foo: 1, bar: 2}

    @impl true
    def get_type(settings, source) do
      assert @settings == settings

      case Process.get(source, nil) do
        nil -> {:error, error(:not_found, "Not found")}
        type -> {:ok, type}
      end
    end

    @impl true
    def put_type(settings, definition) do
      assert @settings == settings
      Process.put(definition.source, definition)
      :ok
    end

    @impl true
    def remove_type(settings, source) do
      assert @settings == settings

      with {:ok, _type} <- get_type(settings, source) do
        Process.delete(source)
        :ok
      end
    end

    @impl true
    def list_types(settings) do
      assert @settings == settings
      Process.get_keys()
    end
  end

  @config %{
    type_storage: %{module: StorageTest, settings: @settings},
    repo: %{module: EctoSQL.TestRepo, dynamic: false}
  }
  @label "Post"
  @source "posts"
  @singular "post"
  @plural "posts"

  defp new_type do
    Type.new(@source, @label, @singular, @plural)
    |> Type.migration_defaults!(fn set ->
      set
      |> Type.add_field!("title", "string", "text", required: true, nullable: false)
      |> Type.add_field!("body", "string", "text", required: false, nullable: true)
    end)
  end

  defp strip_ephemeral(type) do
    case type do
      {:ok, type} -> {:ok, Map.put(type, :ephemeral, %{})}
      type -> Map.put(type, :ephemeral, %{})
    end
  end

  describe "test store" do
    test "init" do
      store = Store.init(@config)
      assert %{config: @config} = store
    end

    test "get type, missing" do
      {:error, err} =
        @config
        |> Store.init()
        |> Store.get_type(@source)

      assert %Error{type: :not_found} = err
    end

    test "put type, get type success" do
      store = Store.init(@config)
      type = new_type()
      assert {:ok, _type} = Store.put_type(store, type)

      assert {:ok, type} == Store.get_type(store, @source) |> strip_ephemeral()
    end

    test "remove type, missing" do
      {:error, err} =
        @config
        |> Store.init()
        |> Store.remove_type(@source)

      assert %Error{type: :not_found} = err
    end

    test "remove type success" do
      store = Store.init(@config)
      type = new_type()
      assert {:ok, _type} = Store.put_type(store, type)

      assert :ok == Store.remove_type(store, @source)
    end
  end

  describe "json store" do
    defp config_json(tmp_dir) do
      %{
        type_storage: %{
          module: EctoEntity.Store.SimpleJson,
          settings: %{directory_path: tmp_dir}
        },
        repo: %{module: TestRepo}
      }
    end

    @tag :tmp_dir
    test "init", %{tmp_dir: tmp_dir} do
      config = config_json(tmp_dir)

      assert %Store{
               config: %{
                 type_storage: %{
                   module: EctoEntity.Store.SimpleJson,
                   settings: %{directory_path: ^tmp_dir}
                 }
               }
             } = Store.init(config)
    end

    @tag :tmp_dir
    test "get type missing", %{tmp_dir: tmp_dir} do
      config = config_json(tmp_dir)

      {:error, err} =
        config
        |> Store.init()
        |> Store.get_type(@source)

      assert %Error{type: :not_found} = err
    end

    @tag :tmp_dir
    test "put type, get type success", %{tmp_dir: tmp_dir} do
      config = config_json(tmp_dir)
      store = Store.init(config)
      type = new_type()
      assert {:ok, _type} = Store.put_type(store, type)

      assert {:ok, type} == Store.get_type(store, @source) |> strip_ephemeral()
    end

    @tag :tmp_dir
    test "remove type, missing", %{tmp_dir: tmp_dir} do
      config = config_json(tmp_dir)

      {:error, err} =
        config
        |> Store.init()
        |> Store.remove_type(@source)

      assert %Error{type: :not_found} = err
    end

    @tag :tmp_dir
    test "remove type success", %{tmp_dir: tmp_dir} do
      config = config_json(tmp_dir)
      store = Store.init(config)
      type = new_type()
      assert {:ok, _type} = Store.put_type(store, type)

      assert :ok == Store.remove_type(store, @source)
    end
  end

  describe "loading" do
    test "load/cast data for definition using repo" do
      store = Store.init(@config)
      type = new_type()
      assert {:ok, type} = Store.put_type(store, type)
      # We now have a type with store ephemerals
      assert %{"title" => "foo"} = EctoEntity.Entity.load(type, %{"title" => "foo"})

      assert_raise ArgumentError, fn ->
        EctoEntity.Entity.load(type, %{"title" => 5})
      end
    end
  end

  describe "queries" do
    setup do
      store = Store.init(@config)
      type = new_type()
      {:ok, type} = Store.put_type(store, type)
      # We now have a type with store ephemerals
      {:ok, type: type}
    end

    test "create", %{type: type} do
      assert {:ok, %{"id" => _}} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
      assert_receive {:query, _, query, params, _}

      assert "insert into posts (id, body, title) values ($1, $2, $3) returning *" =
               String.downcase(query)

      assert [_, "bar", "foo"] = params
    end

    test "create with bad source", %{type: type} do
      assert {:ok, %{"id" => _}} =
               Store.insert(%{type | source: "posts;!=#"}, %{"title" => "foo"})

      assert_receive {:query, _, query, params, _}
      assert "insert into posts (id, title) values ($1, $2) returning *" = String.downcase(query)
      assert [_, "foo"] = params
    end

    test "create with bad field", %{type: type} do
      assert {:ok, %{"id" => _}} = Store.insert(type, %{"title';''='" => "foo"})
      assert_receive {:query, _, query, params, _}
      assert "insert into posts (id, title) values ($1, $2) returning *" = String.downcase(query)
      assert [_, "foo"] = params
    end

    test "list", %{type: type} do
      assert [] = Store.list(type)
      assert_receive {:query, _, query, params, _}
      assert "select * from posts" = String.downcase(query)
      assert [] = params
    end

    test "list with bad source", %{type: type} do
      assert [] = Store.list(%{type | source: "posts;!=#"})
      assert_receive {:query, _, query, params, _}
      assert "select * from posts" = String.downcase(query)
      assert [] = params
    end

    test "update", %{type: type} do
      assert {:ok, %{"id" => _}} = Store.update(type, %{"id" => 5}, title: "foo", body: "bar")
      assert_receive {:query, _, query, params, _}
      assert "update posts set body=$1, title=$2 where id=$3 returning *" = String.downcase(query)
      assert ["bar", "foo", 5] = params
    end

    test "update with bad source", %{type: type} do
      assert {:ok, %{"id" => _}} =
               Store.update(%{type | source: "posts;!=#"}, %{"id" => 5}, title: "foo")

      assert_receive {:query, _, query, params, _}
      assert "update posts set title=$1 where id=$2 returning *" = String.downcase(query)
      assert ["foo", 5] = params
    end

    test "update with bad field", %{type: type} do
      assert {:ok, %{"id" => _}} = Store.update(type, %{"id" => 5}, %{"title';''='" => "foo"})
      assert_receive {:query, _, query, params, _}
      assert "update posts set title=$1 where id=$2 returning *" = String.downcase(query)
      assert ["foo", 5] = params
    end

    test "delete", %{type: type} do
      assert {:ok, 1} = Store.delete(type, %{"id" => 5})
      assert_receive {:query, _, query, params, _}
      assert "delete from posts where id=$1 returning *" = String.downcase(query)
      assert [5] = params
    end

    test "delete with bad source", %{type: type} do
      assert {:ok, 1} = Store.delete(%{type | source: "posts;!=#"}, %{"id" => 5})
      assert_receive {:query, _, query, params, _}
      assert "delete from posts where id=$1 returning *" = String.downcase(query)
      assert [5] = params
    end

    test "remove all data", %{type: type} do
      assert {:ok, 1} = Store.remove_all_data(type)
      assert_receive {:query, _, query, params, _}
      assert "delete from posts returning *" = String.downcase(query)
      assert [] = params
    end

    test "drop table", %{type: type} do
      assert :ok = Store.drop_table(type)
      assert_receive {:query, _, query, params, _}
      assert "drop table posts" = String.downcase(query)
      assert [] = params
    end
  end
end
