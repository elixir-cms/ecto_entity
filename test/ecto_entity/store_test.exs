defmodule EctoEntity.StoreTest do
  use ExUnit.Case, async: true

  alias EctoEntity.Store
  alias EctoEntity.Type

  @settings %{foo: 1, bar: 2}

  defmodule StorageTest do
    @behaviour EctoEntity.Store.Storage
    @settings %{foo: 1, bar: 2}

    @impl true
    def get_type(settings, source) do
      assert @settings == settings
      Process.get(source, nil)
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

  @config %{type_storage: %{module: StorageTest, settings: @settings}}
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

  test "init" do
    store = Store.init(@config)
    assert %{config: @config} = store
  end

  test "get type, missing" do
    type =
      @config
      |> Store.init()
      |> Store.get_type(@source)

    assert nil == type
  end

  test "put type, get type success" do
    store = Store.init(@config)
    type = new_type()
    assert :ok = Store.put_type(store, type)

    assert type == Store.get_type(store, @source)
  end
end
