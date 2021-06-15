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
      assert :ok = Store.put_type(store, type)

      assert {:ok, type} == Store.get_type(store, @source) |> strip_ephemeral()
    end
  end

  describe "json store" do
    @tag :tmp_dir
    test "init", %{tmp_dir: tmp_dir} do
      config = %{
        type_storage: %{
          module: EctoEntity.Store.SimpleJson,
          settings: %{directory_path: tmp_dir}
        },
        repo: %{module: TestRepo}
      }

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
      config = %{
        type_storage: %{module: EctoEntity.Store.SimpleJson, settings: %{directory_path: tmp_dir}},
        repo: %{module: TestRepo}
      }

      {:error, err} =
        config
        |> Store.init()
        |> Store.get_type(@source)

      assert %Error{type: :not_found} = err
    end

    @tag :tmp_dir
    test "put type, get type success", %{tmp_dir: tmp_dir} do
      config = %{
        type_storage: %{module: EctoEntity.Store.SimpleJson, settings: %{directory_path: tmp_dir}},
        repo: %{module: TestRepo}
      }

      store = Store.init(config)
      type = new_type()
      assert :ok = Store.put_type(store, type)

      assert {:ok, type} == Store.get_type(store, @source) |> strip_ephemeral()
    end
  end

  describe "loading" do
    test "load/cast data for definition using repo" do
      store = Store.init(@config)
      type = new_type()
      assert :ok = Store.put_type(store, type)
      {:ok, type} = Store.get_type(store, @source)
      # We now have a type with store ephemerals
      assert %{"title" => "foo"} = EctoEntity.Entity.load(type, %{"title" => "foo"})

      assert_raise ArgumentError, fn ->
        EctoEntity.Entity.load(type, %{"title" => 5})
      end
    end
  end

  describe "queries" do
    test "create" do
      store = Store.init(@config)
      type = new_type()
      assert :ok = Store.put_type(store, type)
      {:ok, type} = Store.get_type(store, @source)
      # We now have a type with store ephemerals
      assert {:ok, 1} = Store.insert(type, %{"title" => "foo"})
      assert_receive {:query, _, query, params, _}
      assert "insert into posts (title) values ($1)" = String.downcase(query)
      assert ["foo"] = params
    end

    test "create with bad source" do
      store = Store.init(@config)
      type = new_type()
      assert :ok = Store.put_type(store, type)
      {:ok, type} = Store.get_type(store, @source)
      # We now have a type with store ephemerals
      assert {:ok, 1} = Store.insert(%{type | source: "posts;!=#"}, %{"title" => "foo"})
      assert_receive {:query, _, query, params, _}
      assert "insert into posts (title) values ($1)" = String.downcase(query)
      assert ["foo"] = params
    end

    test "create with bad field" do
      store = Store.init(@config)
      type = new_type()
      assert :ok = Store.put_type(store, type)
      {:ok, type} = Store.get_type(store, @source)
      # We now have a type with store ephemerals
      assert {:ok, 1} = Store.insert(type, %{"title';''='" => "foo"})
      assert_receive {:query, _, query, params, _}
      assert "insert into posts (title) values ($1)" = String.downcase(query)
      assert ["foo"] = params
    end
  end
end
