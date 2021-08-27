defmodule EctoEntity.SqliteTest do
  @moduledoc """
  Slightly rough and tumble test until we get migrations in order.
  This allows us to test actual SQL, end to end.
  """
  use ExUnit.Case, async: true

  alias EctoEntity.Store
  alias EctoEntity.Type
  require Logger

  defmodule Repo do
    use Ecto.Repo, otp_app: :ecto_entity, adapter: Ecto.Adapters.SQLite3
  end

  def activate_repo(dir) do
    options = [name: nil, database: Path.join(dir, "database.db"), log: false]
    Repo.__adapter__().storage_up(options)
    {:ok, repo} = Repo.start_link(options)
    Repo.put_dynamic_repo(repo)
    repo
  end

  @label "Post"
  @source "posts"
  @singular "post"
  @plural "posts"

  def create_table(repo) do
    {:ok, _result} =
      Ecto.Adapters.SQL.query(
        repo,
        "create table #{@source} (id uuid, title text, body text)",
        []
      )
  end

  defp get_config(tmp_dir, repo) do
    %{
      type_storage: %{
        module: EctoEntity.Store.SimpleJson,
        settings: %{directory_path: Path.join(tmp_dir, "store")}
      },
      repo: %{module: Repo, dynamic: repo}
    }
  end

  defp new_type do
    Type.new(@source, @label, @singular, @plural)
    |> Type.migration_defaults!(fn set ->
      set
      |> Type.add_field!("title", "string", "text", required: true, nullable: false)
      |> Type.add_field!("body", "string", "text", required: false, nullable: true)
    end)
  end

  def bootstrap(dir) do
    repo = activate_repo(dir)
    create_table(repo)
    config = get_config(dir, repo)
    type = new_type()
    store = Store.init(config)
    {:ok, type} = Store.put_type(store, type)
    # Now we have a type set up with a database created by cheating
    # We've also enriched it with ephemerals from the store
    # It is now fully convenient
    type
  end

  @tag :tmp_dir
  test "create", %{tmp_dir: dir} do
    type = bootstrap(dir)
    assert {:ok, _entity} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    #assert %{"id" => _entity_id, "title" => "foo", "body" => "bar"} = entity
    assert [%{"title" => "foo", "body" => "bar"}] = Store.list(type)
  end

  @tag :tmp_dir
  test "update", %{tmp_dir: dir} do
    type = bootstrap(dir)
    assert {:ok, _entity} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    #assert %{"id" => entity_id, "title" => "foo", "body" => "bar"} = entity
    assert [%{"id" => entity_id, "title" => "foo", "body" => "bar"} = entity] = Store.list(type)
    assert {:ok, _} = Store.update(type, entity, title: "baz")
    assert [%{"id" => ^entity_id, "title" => "baz", "body" => "bar"}] = Store.list(type)
  end

  @tag :tmp_dir
  test "delete", %{tmp_dir: dir} do
    type = bootstrap(dir)
    assert {:ok, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    assert [%{"id" => _entity_id, "title" => "foo", "body" => "bar"} = entity] = Store.list(type)
    assert {:ok, _} = Store.delete(type, entity)
    assert [] = Store.list(type)
  end

  @tag :tmp_dir
  test "remove all data", %{tmp_dir: dir} do
    type = bootstrap(dir)
    assert {:ok, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    assert {:ok, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    assert [%{}, %{}] = Store.list(type)
    assert {:ok, _} = Store.remove_all_data(type)
    assert [] = Store.list(type)
  end

  @tag :tmp_dir
  test "drop table", %{tmp_dir: dir} do
    type = bootstrap(dir)
    assert {:ok, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    assert {:ok, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
    assert [%{}, %{}] = Store.list(type)
    assert :ok = Store.drop_table(type)
    assert {:error, _} = Store.insert(type, %{"title" => "foo", "body" => "bar"})
  end
end
