defmodule EctoEntityTest do
  use ExUnit.Case
  doctest EctoEntity

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

    assert %{"title" => "string"} == fields
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
end
