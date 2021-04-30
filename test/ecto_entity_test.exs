defmodule EctoEntityTest do
  use ExUnit.Case, async: true
  doctest EctoEntity.Type

  alias EctoEntity.Type

  @label "Post"
  @source "posts"
  @singular "post"
  @plural "posts"

  test "create type" do
    type = Type.new(@source, @label, @singular, @plural)

    assert %{
             source: @source,
             label: @label,
             singular: @singular,
             plural: @plural,
             fields: %{},
             changesets: %{},
             migrations: []
           } = type
  end

  test "add field" do
    type = Type.new(@source, @label, @singular, @plural)

    %{
      fields: fields,
      changesets: _changesets,
      migrations: [migration]
    } =
      Type.add_field(type, "title", "string", "string",
        nullable: false,
        indexed: true,
        unique: false,
        required: true,
        length: %{max: 200}
      )

    assert %{
             id: _,
             created_at: _,
             set: [
               %{
                 type: "add_field",
                 identifier: "title",
                 field_type: "string",
                 storage_type: "string",
                 persistence_options: %{
                   nullable: false,
                   indexed: true,
                   unique: false
                 },
                 validation_options: %{
                   required: true,
                   length: %{max: 200}
                 }
               }
             ]
           } = migration

    assert %{
             "title" => %{
               field_type: "string",
               storage_type: "string",
               persistence_options: %{
                 nullable: false,
                 indexed: true,
                 unique: false
               },
               validation_options: %{
                 required: true,
                 length: %{max: 200}
               },
               filters: [],
               meta: %{}
             }
           } == fields
  end

  test "add timestamps" do
    type = Type.new(@source, @label, @singular, @plural)

    %{
      fields: fields,
      changesets: _changesets,
      migrations: [migration]
    } = Type.add_timestamps(type)

    assert %{
             id: _,
             created_at: _,
             set: [
               %{
                 type: "add_timestamps"
               }
             ]
           } = migration

    assert %{"inserted_at" => "naive_datetime", "updated_at" => "naive_datetime"} == fields
  end

  test "add primary key, default uuid" do
    type = Type.new(@source, @label, @singular, @plural)

    %{
      fields: fields,
      changesets: _changesets,
      migrations: [migration]
    } = Type.add_primary_key(type)

    assert %{
             id: _,
             created_at: _,
             set: [
               %{
                 type: "add_primary_key",
                 primary_type: "uuid"
               }
             ]
           } = migration

    assert %{"id" => "binary_id"} == fields
  end

  test "add primary key, force integer" do
    type = Type.new(@source, @label, @singular, @plural)

    %{
      fields: fields,
      changesets: _changesets,
      migrations: [migration]
    } = Type.add_primary_key(type, true)

    assert %{
             id: _,
             created_at: _,
             set: [
               %{
                 type: "add_primary_key",
                 primary_type: "integer"
               }
             ]
           } = migration

    assert %{"id" => "id"} == fields
  end

  test "migration defaults" do
    type = Type.new(@source, @label, @singular, @plural)

    %{
      fields: fields,
      changesets: _changesets,
      migrations: [migration]
    } =
      Type.migration_defaults!(type, fn set ->
        set
      end)

    assert %{
             id: _,
             created_at: _,
             set: [
               %{
                 type: "add_primary_key",
                 primary_type: "uuid"
               },
               %{
                 type: "add_timestamps"
               }
             ]
           } = migration

    assert %{
             "id" => "binary_id",
             "inserted_at" => "naive_datetime",
             "updated_at" => "naive_datetime"
           } == fields
  end

  test "alter field, separate migration sets" do
    type = Type.new(@source, @label, @singular, @plural)

    type =
      type
      |> Type.add_field("title", "string", "string",
        nullable: false,
        indexed: true,
        unique: true,
        required: true,
        length: %{max: 200}
      )
      |> Type.alter_field!("title",
        make_nullable: true,
        drop_index: true,
        remove_uniqueness: true,
        set_default: "foo",
        required: false
      )

    %{migrations: [_, %{set: [migration]}], fields: %{"title" => field_options}} = type

    assert %{
             type: "alter_field",
             identifier: "title",
             persistence_options: %{
               make_nullable: true,
               drop_index: true,
               remove_uniqueness: true,
               set_default: "foo"
             },
             validation_options: %{
               required: false
             }
           } = migration

    assert %{
             field_type: "string",
             storage_type: "string",
             persistence_options: %{
               nullable: true,
               indexed: false,
               unique: false,
               default: "foo"
             },
             validation_options: %{
               required: false,
               length: %{max: 200}
             },
             filters: [],
             meta: %{}
           } = field_options
  end

  test "alter field, same migration set" do
    type = Type.new(@source, @label, @singular, @plural)

    type =
      type
      |> Type.migration_set(fn set ->
        set
        |> Type.add_field("title", "string", "string",
          nullable: false,
          indexed: true,
          unique: true,
          required: true,
          length: %{max: 200}
        )
        |> Type.alter_field!(type, "title",
          make_nullable: true,
          drop_index: true,
          remove_uniqueness: true,
          set_default: "foo",
          required: false
        )
      end)

    %{migrations: [%{set: [_, migration]}], fields: %{"title" => field_options}} = type

    assert %{
             type: "alter_field",
             identifier: "title",
             persistence_options: %{
               make_nullable: true,
               drop_index: true,
               remove_uniqueness: true,
               set_default: "foo"
             },
             validation_options: %{
               required: false
             }
           } = migration

    assert %{
             field_type: "string",
             storage_type: "string",
             persistence_options: %{
               nullable: true,
               indexed: false,
               unique: false,
               default: "foo"
             },
             validation_options: %{
               required: false,
               length: %{max: 200}
             },
             filters: [],
             meta: %{}
           } = field_options
  end

  test "alter field, invalid, field doesn't exist" do
    type = Type.new(@source, @label, @singular, @plural)

    assert_raise RuntimeError, fn ->
      Type.alter_field!(type, "title",
        make_nullable: true,
        drop_index: true,
        remove_uniqueness: true,
        set_default: "foo",
        required: false
      )
    end
  end
end
