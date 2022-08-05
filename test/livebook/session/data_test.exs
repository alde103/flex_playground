defmodule Livebook.Session.DataTest do
  use ExUnit.Case, async: true

  import Livebook.TestHelpers

  alias Livebook.Session.Data
  alias Livebook.{Delta, Notebook}
  alias Livebook.Notebook.Cell
  alias Livebook.Users.User

  @eval_resp {:ok, [1, 2, 3]}
  @eval_meta %{evaluation_time_ms: 10}
  @smart_cell_definitions [%{kind: "text", name: "Text", requirement: nil}]
  @cid "__anonymous__"

  describe "new/1" do
    test "called with no arguments defaults to a blank notebook" do
      assert %{notebook: %{sections: []}, cell_infos: cell_infos, section_infos: section_infos} =
               Data.new()

      assert map_size(cell_infos) == 1
      assert map_size(section_infos) == 1
    end

    test "called with a notebook, sets default cell and section infos" do
      notebook = %{
        Notebook.new()
        | sections: [
            %{
              Notebook.Section.new()
              | id: "s1",
                cells: [%{Notebook.Cell.new(:code) | id: "c1"}]
            }
          ]
      }

      assert %{cell_infos: %{"c1" => %{}}, section_infos: %{"s1" => %{}}} = Data.new(notebook)
    end

    test "called with a notebook, computes cell snapshots" do
      notebook = %{
        Notebook.new()
        | sections: [
            %{
              Notebook.Section.new()
              | id: "s1",
                cells: [%{Notebook.Cell.new(:code) | id: "c1"}]
            }
          ]
      }

      assert %{cell_infos: %{"c1" => %{eval: %{snapshot: snapshot}}}} = Data.new(notebook)
      assert snapshot != {nil, nil}
    end
  end

  describe "apply_operation/2 given :insert_section" do
    test "adds new section to notebook and section info" do
      data = Data.new()

      operation = {:insert_section, @cid, 0, "s1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1"}]
                },
                section_infos: %{"s1" => _}
              }, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_notebook_attributes" do
    test "returns an error given an unknown attribute key" do
      data = Data.new()

      attrs = %{unknown: :value}
      operation = {:set_notebook_attributes, @cid, attrs}

      assert :error = Data.apply_operation(data, operation)
    end

    test "updates notebook with the given attributes" do
      data = Data.new()

      attrs = %{persist_outputs: true}
      operation = {:set_notebook_attributes, @cid, attrs}

      assert {:ok,
              %{
                notebook: %{persist_outputs: true}
              }, _} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :insert_section_into" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:insert_section_into, @cid, "nonexistent", 0, "s1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "adds new section below the given one and section info" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:insert_section_into, @cid, "s1", 0, "s2"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1"}, %{id: "s2"}]
                },
                section_infos: %{"s2" => _}
              }, []} = Data.apply_operation(data, operation)
    end

    test "moves cells below the given index to the newly inserted section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}}
        ])

      operation = {:insert_section_into, @cid, "s1", 1, "s2"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{cells: [%{id: "c1"}]}, %{cells: [%{id: "c2"}]}]
                }
              }, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_section_parent" do
    test "returns an error given invalid section id" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:set_section_parent, @cid, "nonexistent", "s1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given invalid parent section id" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:set_section_parent, @cid, "s1", "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error if the parent section is below the given section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"}
        ])

      operation = {:set_section_parent, @cid, "s1", "s2"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error if the parent section is a branch section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:set_section_parent, @cid, "s3", "s2"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error if there are sections branching out from the given section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:set_section_parent, @cid, "s3", "s2"}
        ])

      operation = {:set_section_parent, @cid, "s2", "s1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "sets parent id on section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"}
        ])

      operation = {:set_section_parent, @cid, "s2", "s1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1", parent_id: nil}, %{id: "s2", parent_id: "s1"}]
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks cells in this and further sections as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:set_section_parent, @cid, "s2", "s1"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "if a cell is evaluating in this section, clears all sections evaluation and queues" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3"]}
        ])

      operation = {:set_section_parent, @cid, "s2", "s1"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :aborted, status: :ready}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s3" => %{evaluating_cell_id: nil, evaluation_queue: []}
                }
              },
              [{:stop_evaluation, %{id: "s2", parent_id: nil}}]} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :unset_section_parent" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:unset_section_parent, @cid, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given section with no parent" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:unset_section_parent, @cid, "s1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "sets parent id on section to nil" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:unset_section_parent, @cid, "s2"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1", parent_id: nil}, %{id: "s2", parent_id: nil}]
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "returns stop evaluation action" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:unset_section_parent, @cid, "s2"}

      assert {:ok, %{}, [{:stop_evaluation, %{id: "s2", parent_id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks cells in this and further sections as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:unset_section_parent, @cid, "s2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "if a cell is evaluating in this section, marks evaluated and evaluating cells as aborted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3"]}
        ])

      operation = {:unset_section_parent, @cid, "s2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :evaluating}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :insert_cell" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:insert_cell, @cid, "nonexistent", 0, :code, "c1", %{}}
      assert :error = Data.apply_operation(data, operation)
    end

    test "adds a new cell to notebook and cell infos" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%Cell.Code{id: "c1"}]}
                  ]
                },
                cell_infos: %{"c1" => _}
              }, []} = Data.apply_operation(data, operation)
    end

    test "initializes client-revision map" do
      client_id = "client1"

      data =
        data_after_operations!([
          {:client_join, client_id, User.new()},
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{sources: %{primary: %{revision_by_client_id: %{^client_id => 0}}}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "given a smart cell, keeps it dead if there is no corresponding definition" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()}
        ])

      operation = {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}}

      assert {:ok, %{cell_infos: %{"c1" => %{status: :dead}}}, []} =
               Data.apply_operation(data, operation)
    end

    test "given a smart cell, marks it as starting if there is a corresponding definition and a runtime" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions}
        ])

      operation = {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}}

      assert {:ok, %{cell_infos: %{"c1" => %{status: :starting}}},
              [{:start_smart_cell, %{id: "c1"}, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "inserting code cell before smart cell does not change its base" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :smart, "c2", %{kind: "text"}},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:smart_cell_started, @cid, "c2", Delta.new(), %{}, nil}
        ])

      operation = {:insert_cell, @cid, "s1", 0, :code, "c3", %{}}

      assert {:ok, %{}, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :delete_section" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:delete_section, @cid, "nonexistent", true}
      assert :error = Data.apply_operation(data, operation)
    end

    test "removes the section from notebook and section info" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:delete_section, @cid, "s1", true}

      assert {:ok,
              %{
                notebook: %{
                  sections: []
                },
                section_infos: section_infos
              }, []} = Data.apply_operation(data, operation)

      refute Map.has_key?(section_infos, "s1")
    end

    test "returns error when cell deletion is disabled for the first cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:delete_section, @cid, "s1", false}
      assert :error = Data.apply_operation(data, operation)
    end

    test "keeps cells when cell deletion is disabled" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}}
        ])

      operation = {:delete_section, @cid, "s2", false}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1", cells: [%{id: "c1"}, %{id: "c2"}]}]
                },
                bin_entries: []
              }, []} = Data.apply_operation(data, operation)
    end

    test "deletes cells when cell deletion is enabled" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"])
        ])

      operation = {:delete_section, @cid, "s2", true}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1", cells: [%{id: "c1"}]}]
                },
                bin_entries: [
                  %{
                    cell: %{id: "c2"},
                    section_id: "s2",
                    section_name: "Section",
                    index: 0,
                    deleted_at: _
                  }
                ]
              },
              [{:forget_evaluation, %{id: "c2"}, %{id: "s2"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale when cells get deleted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          # Evaluate both cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"])
        ])

      operation = {:delete_section, @cid, "s1", true}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{validity: :stale}}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks cells in this and further sections as stale if branching section is deleted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:delete_section, @cid, "s2", false}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "does not mark cells in further sections as stale if branching section is deleted with cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:delete_section, @cid, "s2", true}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :evaluated}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "returns an error if the section has branching sections" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:delete_section, @cid, "s1", false}

      assert :error = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :delete_cell" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:delete_cell, @cid, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating, cencels section evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :ready}}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: []}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "removes the cell from notebook and section info, adds to deleted cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{cells: []}]
                },
                cell_infos: cell_infos,
                bin_entries: [
                  %{
                    cell: %{id: "c1"},
                    section_id: "s1",
                    section_name: "Section",
                    index: 0,
                    deleted_at: _
                  }
                ]
              }, _actions} = Data.apply_operation(data, operation)

      refute Map.has_key?(cell_infos, "c1")
    end

    test "unqueues the cell if it's queued for evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:delete_cell, @cid, "c2"}

      assert {:ok,
              %{
                section_infos: %{"s1" => %{evaluation_queue: []}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          # Evaluate both cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"])
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{validity: :stale}}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks child automatically reevaluating cells for evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_cell_attributes, @cid, "c2", %{reevaluate_automatically: true}},
          # Evaluate both cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"])
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :evaluating}}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "deleting a markdown cell does not change child cell validity" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :markdown, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          # Evaluate the Code cell
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c2"])
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{validity: :evaluated}}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "returns forget evaluation action" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok, _data, [{:forget_evaluation, %{id: "c1"}, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "given an alive smart cell returns a stop action" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}},
          {:smart_cell_started, @cid, "c1", Delta.new(), %{}, nil}
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok, _data, [{:stop_smart_cell, %{id: "c1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "deleting evaluated code cell before smart cell changes its base" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :smart, "c2", %{kind: "text"}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:smart_cell_started, @cid, "c2", Delta.new(), %{}, nil},
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}
        ])

      operation = {:delete_cell, @cid, "c1"}

      assert {:ok, %{},
              [
                {:forget_evaluation, _, _},
                {:set_smart_cell_base, %{id: "c2"}, %{id: "s1"},
                 {%{id: "setup"}, %{id: "setup-section"}}}
              ]} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :restore_cell" do
    test "returns an error if cell with the given id is not in the bin" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:restore_cell, @cid, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error if there are no sections to restore to" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:delete_section, @cid, "s1", true}
        ])

      operation = {:restore_cell, @cid, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "if the original section exists, restores cell at the index of deletion" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:delete_cell, @cid, "c2"}
        ])

      operation = {:restore_cell, @cid, "c2"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s1", cells: [%{id: "c1"}, %{id: "c2"}, %{id: "c3"}]}]
                },
                cell_infos: %{"c2" => %{}},
                bin_entries: []
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "if the original section does not exist, restores cell at the end of the notebook" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:delete_section, @cid, "s1", true}
        ])

      operation = {:restore_cell, @cid, "c1"}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{id: "s2", cells: [%{id: "c2"}, %{id: "c1"}]}]
                },
                cell_infos: %{"c2" => %{}},
                bin_entries: []
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "given a smart cell starts it when there is a matching definition" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}},
          {:delete_cell, @cid, "c1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions}
        ])

      operation = {:restore_cell, @cid, "c1"}

      assert {:ok, %{cell_infos: %{"c1" => %{status: :starting}}},
              [{:start_smart_cell, %{id: "c1"}, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :move_cell" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:move_cell, @cid, "nonexistent", 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given no offset" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:move_cell, @cid, "c1", 0}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error if the cell is evaluating and would move to a different section" do
      # In practice we don't want evaluating cells to be moved between
      # a section and a branching section, however for simplicity we
      # do the same for other sections

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:move_cell, @cid, "c1", 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "given negative offset moves the cell and marks relevant cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:insert_cell, @cid, "s1", 3, :code, "c4", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_cell, @cid, "c3", -1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{id: "c1"}, %{id: "c3"}, %{id: "c2"}, %{id: "c4"}]
                    }
                  ]
                },
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "given positive offset moves the cell and marks relevant cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:insert_cell, @cid, "s1", 3, :code, "c4", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_cell, @cid, "c2", 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{id: "c1"}, %{id: "c3"}, %{id: "c2"}, %{id: "c4"}]
                    }
                  ]
                },
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "allows moving cells between sections" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c4", %{}}
        ])

      operation = {:move_cell, @cid, "c2", 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{id: "c1"}]},
                    %{cells: [%{id: "c2"}, %{id: "c3"}, %{id: "c4"}]}
                  ]
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks relevant cells in further sections as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:move_cell, @cid, "c1", 1}

      assert {:ok,
              %{
                cell_infos: %{"c3" => %{eval: %{validity: :stale}}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "moving a markdown cell does not change validity" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :markdown, "c2", %{}},
          # Evaluate the Code cell
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:move_cell, @cid, "c2", -1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "affected queued cell is unqueued" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          # Evaluate the Code cell
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:move_cell, @cid, "c2", -1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{status: :ready}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "does not invalidate the moved cell if the order of Code cells stays the same" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :markdown, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c3"])
        ])

      operation = {:move_cell, @cid, "c1", 1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "invalidates only relevant cells if a cell is moved within a branch section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_cell, @cid, "c2", 1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "invalidates cells only in relevant branch sections" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:insert_section, @cid, 3, "s4"},
          {:insert_cell, @cid, "s4", 0, :code, "c5", %{}},
          {:set_section_parent, @cid, "s3", "s2"},
          {:set_section_parent, @cid, "s4", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4", "c5"])
        ])

      operation = {:move_cell, @cid, "c2", 1}

      # Section s4 is independent of section s2, so it shouldn't be invalidated

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}},
                  "c5" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "moving a cell back and forth doesn't impact validity" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      {:ok, data_moved, []} = Data.apply_operation(data, {:move_cell, @cid, "c2", -1})
      {:ok, data_reversed, []} = Data.apply_operation(data_moved, {:move_cell, @cid, "c2", 1})

      assert data_reversed == data
    end
  end

  describe "apply_operation/2 given :move_section" do
    test "returns an error given invalid section id" do
      data = Data.new()
      operation = {:move_section, @cid, "nonexistent", 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given no offset" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"}
        ])

      operation = {:move_section, @cid, "s2", 0}
      assert :error = Data.apply_operation(data, operation)
    end

    test "given negative offset moves the section and marks relevant cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c4", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_section, @cid, "s2", -1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{id: "c3"}, %{id: "c4"}]
                    },
                    %{
                      cells: [%{id: "c1"}, %{id: "c2"}]
                    }
                  ]
                },
                cell_infos: %{
                  "c1" => %{eval: %{validity: :stale}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "given positive offset moves the section and marks relevant cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c4", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_section, @cid, "s1", 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{id: "c3"}, %{id: "c4"}]
                    },
                    %{
                      cells: [%{id: "c1"}, %{id: "c2"}]
                    }
                  ]
                },
                cell_infos: %{
                  "c1" => %{eval: %{validity: :stale}},
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks relevant cells in further sections as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      operation = {:move_section, @cid, "s1", 1}

      assert {:ok,
              %{
                cell_infos: %{"c3" => %{eval: %{validity: :stale}}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "moving a section with only markdown cells does not change validity" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s2", 0, :markdown, "c2", %{}},
          # Evaluate the Code cell
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:move_section, @cid, "s2", -1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "affected queued cells are unqueued" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          # Evaluate the Code cell
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:move_section, @cid, "s2", -1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{status: :ready}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "does not invalidate cells in moved section if the order of Code cells stays the same" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:insert_section, @cid, 3, "s4"},
          # Add cells
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s2", 0, :markdown, "c2", %{}},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s4", 0, :markdown, "c4", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c3"])
        ])

      operation = {:move_section, @cid, "s4", -1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "does not invalidate any cells if a branching sections is moved" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:insert_section, @cid, 3, "s4"},
          {:insert_cell, @cid, "s4", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"])
        ])

      operation = {:move_section, @cid, "s2", 1}

      # Section s2 is branching, so moving it should have no impact on validity

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :evaluated}},
                  "c4" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "returns an error when moving a regular section below one of its child sections" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:move_section, @cid, "s1", 1}

      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error when moving a child section above its parent section" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:set_section_parent, @cid, "s2", "s1"}
        ])

      operation = {:move_section, @cid, "s2", -1}

      assert :error = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :queue_cells_evaluation" do
    test "returns an error given an empty list of cells" do
      data = Data.new()
      operation = {:queue_cells_evaluation, @cid, []}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:queue_cells_evaluation, @cid, ["nonexistent"]}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given non-Code cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :markdown, "c1", %{}}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c1"]}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error for an evaluating cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c1"]}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns connect runtime action if there is no runtime and this is the first evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c1"]}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{eval: %{status: :queued}}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: ["c1"]}}
              }, [:connect_runtime]} = Data.apply_operation(data, operation)
    end

    test "only queues the cell if runtime start has already been requested" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c2"]}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{status: :queued}},
                  "c2" => %{eval: %{status: :queued}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: ["c1", "c2"]}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks the cell as evaluating if the corresponding section is idle" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"])
        ])

      operation = {:queue_cells_evaluation, @cid, ["c1"]}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{eval: %{status: :evaluating}}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "returns start evaluation action if the corresponding section is idle" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"])
        ])

      operation = {:queue_cells_evaluation, @cid, ["c1"]}

      assert {:ok, _data, [{:start_evaluation, %{id: "c1"}, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks the cell as queued if the corresponding section is already evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c2"]}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :queued}}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: ["c2"]}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks the cell as queued if a previous section is already evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c2"]}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :queued}}},
                section_infos: %{
                  "s1" => %{evaluating_cell_id: "c1", evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: ["c2"]}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "queues previous unevaluated and stale cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c4", %{}},
          # Evaluate first 2 cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          # Evaluate the first cell, so the second becomes stale
          evaluate_cells_operations(["c1"])
        ])

      # The above leads to:
      #
      # Section 1:
      # * cell 1 - evaluated
      # * cell 2 - stale
      # Section 2:
      # * cell 3 - fresh
      # * cell 4 - fresh
      #
      # Queuing cell 4 should also queue cell 3 and cell 2,
      # so that they all become evaluated.

      operation = {:queue_cells_evaluation, @cid, ["c4"]}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{status: :evaluating}},
                  "c3" => %{eval: %{status: :queued}},
                  "c4" => %{eval: %{status: :queued}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: "c2", evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: ["c3", "c4"]}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "queues only required parent cells when queueing a branch cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s3", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"])
        ])

      operation = {:queue_cells_evaluation, @cid, ["c3"]}

      # Cell 3 depends directly on cell 1, so cell 2 shouldn't be queued

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :fresh, status: :evaluating}},
                  "c2" => %{eval: %{validity: :fresh, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :queued}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: "c1", evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s3" => %{evaluating_cell_id: nil, evaluation_queue: ["c3"]}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks first branch cell as queued if a regular section is evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c3"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c2"]}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{status: :queued}},
                  "c3" => %{eval: %{status: :evaluating}}
                },
                section_infos: %{
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: ["c2"]},
                  "s3" => %{evaluating_cell_id: "c3", evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks first branch cell as evaluating if no regular section is evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:queue_cells_evaluation, @cid, ["c2"]}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :evaluating}}},
                section_infos: %{"s2" => %{evaluating_cell_id: "c2", evaluation_queue: []}}
              },
              [{:start_evaluation, %{id: "c2"}, %{id: "s2"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks the second branch cell as evaluating if the first one is evaluated, even if a regular section is evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          {:queue_cells_evaluation, @cid, ["c4"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c3"]}

      assert {:ok,
              %{
                cell_infos: %{
                  "c3" => %{eval: %{status: :evaluating}},
                  "c4" => %{eval: %{status: :evaluating}}
                },
                section_infos: %{
                  "s2" => %{evaluating_cell_id: "c3", evaluation_queue: []},
                  "s3" => %{evaluating_cell_id: "c4", evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "marks regular cell as evaluating if only a branch cell is evaluating" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2"]}
        ])

      operation = {:queue_cells_evaluation, @cid, ["c3"]}

      assert {:ok,
              %{
                cell_infos: %{"c3" => %{eval: %{status: :evaluating}}},
                section_infos: %{"s3" => %{evaluating_cell_id: "c3", evaluation_queue: []}}
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :evaluation_started" do
    test "updates cell evaluation digest" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:evaluation_started, @cid, "c1", "digest"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{
                    eval: %{evaluation_digest: "digest"}
                  }
                }
              }, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :add_cell_evaluation_output" do
    test "updates the cell outputs" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_output, @cid, "c1", {:stdout, "Hello!"}}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{outputs: [{1, {:stdout, "Hello!"}}]}]
                    }
                  ]
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "adds output even after the cell finished evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:add_cell_evaluation_output, @cid, "c1", {:stdout, "Hello!"}}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{outputs: [{2, {:stdout, "Hello!"}}, _result]}]
                    }
                  ]
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "sets dirty flag to true if outputs are persisted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:set_notebook_attributes, @cid, %{persist_outputs: true}},
          {:mark_as_not_dirty, @cid}
        ])

      operation = {:add_cell_evaluation_output, @cid, "c1", {:stdout, "Hello!"}}

      assert {:ok, %{dirty: true}, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :add_cell_evaluation_response" do
    test "updates the cell outputs" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation =
        {:add_cell_evaluation_response, @cid, "c1", {:ok, [1, 2, 3]}, %{evaluation_time_ms: 10}}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      cells: [%{outputs: [{1, {:ok, [1, 2, 3]}}]}]
                    }
                  ]
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks the cell as ready" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{eval: %{status: :ready}}},
                section_infos: %{"s1" => %{evaluating_cell_id: nil, evaluation_queue: []}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "preserves validity status" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          # Evaluate the first cell
          evaluate_cells_operations(["c1"]),
          # Start evaluating the second cell
          {:queue_cells_evaluation, @cid, ["c2"]},
          # Remove the first cell, marking the second as stale
          {:delete_cell, @cid, "c1"}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c2", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{validity: :stale}}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks next queued cell in this section as evaluating if there is one" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :evaluating}}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c2", evaluation_queue: []}}
              },
              [{:start_evaluation, %{id: "c2"}, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks next queued cell in a further section as evaluating if there is one" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{"c2" => %{eval: %{status: :evaluating}}},
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: "c2", evaluation_queue: []}
                }
              },
              [{:start_evaluation, %{id: "c2"}, %{id: "s2"}}]} =
               Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          # Evaluate all cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"]),
          # Queue the first cell again
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{validity: :stale}},
                  "c3" => %{eval: %{validity: :stale}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks evaluated child cells as stale in relevant branch sections" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c3", %{}},
          {:insert_section, @cid, 3, "s4"},
          {:insert_cell, @cid, "s4", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s3", "s2"},
          {:set_section_parent, @cid, "s4", "s1"},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3", "c4"]),
          # Queue the second cell again
          {:queue_cells_evaluation, @cid, ["c2"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c2", @eval_resp, @eval_meta}

      # Section s4 is independent of section s2, so it shouldn't be invalidated

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated}},
                  "c2" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :evaluated}}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "marks child automatically reevaluating cells for evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_cell_attributes, @cid, "c3", %{reevaluate_automatically: true}},
          # Evaluate all cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"]),
          # Queue the first cell again
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{status: :evaluating}},
                  "c3" => %{eval: %{status: :queued}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "does not mark child automatically reevaluating cells for evaluation if they are fresh" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_cell_attributes, @cid, "c2", %{reevaluate_automatically: true}},
          # Evaluate all cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{status: :ready, validity: :evaluated}},
                  "c2" => %{eval: %{status: :ready, validity: :fresh}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "if bound input value changes during cell evaluation, the cell is marked as stale afterwards" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:add_cell_evaluation_response, @cid, "c2", @eval_resp, @eval_meta},
          # Make the Code cell evaluating
          {:queue_cells_evaluation, @cid, ["c2"]},
          # Bind the input (effectively read the current value)
          {:bind_input, @cid, "c2", "i1"},
          # Change the input value, while the cell is evaluating
          {:set_input_value, @cid, "i1", "stuff"}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c2", @eval_resp, @eval_meta}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{validity: :stale}}
                }
              }, _} = Data.apply_operation(data, operation)
    end

    test "adds evaluation time to the response" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation =
        {:add_cell_evaluation_response, @cid, "c1", {:ok, [1, 2, 3]}, %{evaluation_time_ms: 10}}

      Process.sleep(10)

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{eval: %{evaluation_time_ms: evaluation_time}}}
              }, []} = Data.apply_operation(data, operation)

      assert evaluation_time >= 10
    end

    test "sets dirty flag to true if outputs are persisted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:set_notebook_attributes, @cid, %{persist_outputs: true}},
          {:mark_as_not_dirty, @cid}
        ])

      operation =
        {:add_cell_evaluation_response, @cid, "c1", {:ok, [1, 2, 3]}, %{evaluation_time_ms: 10}}

      assert {:ok, %{dirty: true}, []} = Data.apply_operation(data, operation)
    end

    test "stores default values for new inputs" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta}

      assert {:ok, %{input_values: %{"i1" => "hey"}}, _} = Data.apply_operation(data, operation)
    end

    test "keeps input values for inputs that existed" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:set_input_value, @cid, "i1", "value"},
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      # Output the same input again
      operation = {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta}

      assert {:ok, %{input_values: %{"i1" => "value"}}, _} = Data.apply_operation(data, operation)
    end

    test "garbage collects input values that are no longer used" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:set_input_value, @cid, "i1", "value"},
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      # This time w don't output the input
      operation = {:add_cell_evaluation_response, @cid, "c1", {:ok, 10}, @eval_meta}

      empty_map = %{}

      assert {:ok, %{input_values: ^empty_map}, _} = Data.apply_operation(data, operation)
    end

    test "does not garbage collect inputs if present in another cell" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:add_cell_evaluation_response, @cid, "c2", {:input, input}, @eval_meta},
          {:set_input_value, @cid, "i1", "value"},
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      # This time w don't output the input
      operation = {:add_cell_evaluation_response, @cid, "c1", {:ok, 10}, @eval_meta}

      assert {:ok, %{input_values: %{"i1" => "value"}}, _} = Data.apply_operation(data, operation)
    end

    test "does not garbage collect inputs if another evaluation is ongoing" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_section, @cid, 1, "s2"},
          {:insert_section, @cid, 2, "s3"},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_section_parent, @cid, "s3", "s1"},
          {:insert_cell, @cid, "s2", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s3", 0, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:set_input_value, @cid, "i1", "value"},
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:queue_cells_evaluation, @cid, ["c2"]}
        ])

      # This time w don't output the input
      operation = {:add_cell_evaluation_response, @cid, "c1", {:ok, 10}, @eval_meta}

      assert {:ok, %{input_values: %{"i1" => "value"}}, _} = Data.apply_operation(data, operation)
    end

    test "evaluating code cell before smart cell changes its base" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :smart, "c2", %{kind: "text"}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:smart_cell_started, @cid, "c2", Delta.new(), %{}, nil},
          {:queue_cells_evaluation, @cid, ["c1"]}
        ])

      operation = {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}

      assert {:ok, %{},
              [{:set_smart_cell_base, %{id: "c2"}, %{id: "s1"}, {%{id: "c1"}, %{id: "s1"}}}]} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :bind_input" do
    test "returns an error given invalid input cell id" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:bind_input, @cid, "c1", "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given non-input cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}}
        ])

      operation = {:bind_input, @cid, "c2", "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "updates Code cell info with binding to the input cell" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:queue_cells_evaluation, @cid, ["c2"]}
        ])

      operation = {:bind_input, @cid, "c2", "i1"}

      bound_to_input_ids = MapSet.new(["i1"])

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{bound_to_input_ids: ^bound_to_input_ids}}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :reflect_main_evaluation_failure" do
    test "clears evaluation queue and marks evaluated and evaluating cells as aborted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3"]}
        ])

      operation = {:reflect_main_evaluation_failure, @cid}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :aborted, status: :ready}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "leaves branching sections unchanged" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          {:queue_cells_evaluation, @cid, ["c3"]}
        ])

      operation = {:reflect_main_evaluation_failure, @cid}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :aborted, status: :ready}},
                  "c2" => %{eval: %{validity: :evaluated, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :evaluating}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: "c3", evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :reflect_evaluation_failure" do
    test "clears section evaluation queue and marks evaluated and evaluating cells as aborted" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          {:queue_cells_evaluation, @cid, ["c3", "c4"]}
        ])

      operation = {:reflect_evaluation_failure, @cid, "s2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated, status: :ready}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :aborted, status: :ready}},
                  "c4" => %{eval: %{validity: :fresh, status: :evaluating}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s3" => %{evaluating_cell_id: "c4", evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :cancel_cell_evaluation" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:cancel_cell_evaluation, @cid, "nonexistent"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error for an evaluated cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"])
        ])

      operation = {:cancel_cell_evaluation, @cid, "c1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating, clears all sections evaluation and queues" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3"]}
        ])

      operation = {:cancel_cell_evaluation, @cid, "c2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :aborted, status: :ready}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating, returns stop evaluation action" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:cancel_cell_evaluation, @cid, "c1"}

      assert {:ok, _data, [{:stop_evaluation, %{id: "s1"}}]} =
               Data.apply_operation(data, operation)
    end

    test "if the cell is evaluating within branched section, clears this section evaluation and queue" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3", "c4"]}
        ])

      operation = {:cancel_cell_evaluation, @cid, "c2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :evaluated, status: :ready}},
                  "c2" => %{eval: %{validity: :aborted, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}},
                  "c4" => %{eval: %{validity: :fresh, status: :evaluating}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s3" => %{evaluating_cell_id: "c4", evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "if the cell is queued, unqueues it" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      operation = {:cancel_cell_evaluation, @cid, "c2"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }, []} = Data.apply_operation(data, operation)
    end

    test "if the cell is queued, unqueues dependent cells that are also queued" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2", "c3"]}
        ])

      operation = {:cancel_cell_evaluation, @cid, "c2"}

      assert {:ok,
              %{
                cell_infos: %{"c3" => %{eval: %{status: :ready}}},
                section_infos: %{"s1" => %{evaluating_cell_id: "c1", evaluation_queue: []}}
              }, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :smart_cell_started" do
    test "returns an error if the cell is dead" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}}
        ])

      operation = {:smart_cell_started, @cid, "c1", Delta.new(), %{}, nil}

      assert :error = Data.apply_operation(data, operation)
    end

    test "marks the cell as alive and updates its source" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}}
        ])

      delta = Delta.new() |> Delta.insert("content")

      operation = {:smart_cell_started, @cid, "c1", delta, %{}, nil}

      assert {:ok, %{cell_infos: %{"c1" => %{status: :started}}}, _actions} =
               Data.apply_operation(data, operation)
    end

    test "updates the cell source and returns a broadcast delta action" do
      client_id = "client1"

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}}
        ])

      delta = Delta.new() |> Delta.insert("content")

      operation = {:smart_cell_started, client_id, "c1", delta, %{}, nil}

      assert {:ok,
              %{
                notebook: %{sections: [%{cells: [%{id: "c1", source: "content"}]}]}
              },
              [{:broadcast_delta, ^client_id, _cell, :primary, ^delta}]} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :update_smart_cell" do
    test "updates the cell attrs, source and returns a broadcast delta action" do
      client_id = "client1"

      delta1 = Delta.new() |> Delta.insert("content")

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}},
          {:smart_cell_started, @cid, "c1", delta1, %{}, nil}
        ])

      attrs = %{"text" => "content!"}
      delta2 = Delta.new() |> Delta.retain(7) |> Delta.insert("!")
      operation = {:update_smart_cell, client_id, "c1", attrs, delta2, false}

      assert {:ok,
              %{
                notebook: %{
                  sections: [%{cells: [%{id: "c1", source: "content!", attrs: ^attrs}]}]
                }
              },
              [{:broadcast_delta, ^client_id, _cell, :primary, ^delta2}]} =
               Data.apply_operation(data, operation)
    end

    test "queues the cell when already evaluated and reevaluate is specified" do
      client_id = "client1"

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}},
          {:smart_cell_started, @cid, "c1", Delta.new(), %{}, nil},
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", @eval_resp, @eval_meta}
        ])

      operation = {:update_smart_cell, client_id, "c1", %{}, Delta.new(), true}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{eval: %{status: :evaluating}}}
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :erase_outputs" do
    test "clears all sections evaluation and queues" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1"]),
          {:queue_cells_evaluation, @cid, ["c2", "c3"]}
        ])

      operation = {:erase_outputs, @cid}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :fresh, status: :ready}},
                  "c2" => %{eval: %{validity: :fresh, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []}
                }
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "removes Code cell outputs" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :markdown, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c3"])
        ])

      operation = {:erase_outputs, @cid}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{
                      id: "s1",
                      cells: [
                        %{id: "c1", outputs: []},
                        %{id: "c2"},
                        %{id: "c3", outputs: []}
                      ]
                    }
                  ]
                }
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_notebook_name" do
    test "updates notebook name with the given string" do
      data = Data.new()

      operation = {:set_notebook_name, @cid, "Cat's guide to life"}

      assert {:ok, %{notebook: %{name: "Cat's guide to life"}}, []} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_section_name" do
    test "returns an error given invalid cell id" do
      data = Data.new()
      operation = {:set_section_name, @cid, "nonexistent", "Chapter 1"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "updates section name with the given string" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:set_section_name, @cid, "s1", "Cat's guide to life"}

      assert {:ok, %{notebook: %{sections: [%{name: "Cat's guide to life"}]}}, []} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :client_join" do
    test "returns an error if the given process is already a client" do
      user = User.new()

      data =
        data_after_operations!([
          {:client_join, @cid, user}
        ])

      operation = {:client_join, @cid, user}
      assert :error = Data.apply_operation(data, operation)
    end

    test "adds the given process and user to their corresponding maps" do
      client_id = "client1"
      %{id: user_id} = user = User.new()
      data = Data.new()

      operation = {:client_join, client_id, user}

      assert {:ok, %{clients_map: %{^client_id => ^user_id}, users_map: %{^user_id => ^user}}, []} =
               Data.apply_operation(data, operation)
    end

    test "adds new entry to the cell revisions map for the client with the latest revision" do
      client1_id = "cid1"
      user = User.new()
      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, user},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      client2_id = "cid2"
      operation = {:client_join, client2_id, user}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{sources: %{primary: %{revision_by_client_id: %{^client2_id => 1}}}}
                }
              }, _} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :client_leave" do
    test "returns an error if the given process is not a client" do
      data = Data.new()

      operation = {:client_leave, @cid}
      assert :error = Data.apply_operation(data, operation)
    end

    test "removes the given process from the client map" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()}
        ])

      operation = {:client_leave, @cid}

      empty_map = %{}
      assert {:ok, %{clients_map: ^empty_map}, []} = Data.apply_operation(data, operation)
    end

    test "removes the corresponding user from users map if it has no more client processes" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()}
        ])

      operation = {:client_leave, @cid}

      empty_map = %{}
      assert {:ok, %{users_map: ^empty_map}, []} = Data.apply_operation(data, operation)
    end

    test "leaves the corresponding user in users map if it has more client processes" do
      %{id: user_id} = user = User.new()
      client1_id = "cid1"
      client2_id = "cid2"

      data =
        data_after_operations!([
          {:client_join, client1_id, user},
          {:client_join, client2_id, user}
        ])

      operation = {:client_leave, client2_id}

      assert {:ok, %{users_map: %{^user_id => ^user}}, []} = Data.apply_operation(data, operation)
    end

    test "removes an entry in the the cell revisions map for the client and purges deltas" do
      client1_id = "cid1"
      client2_id = "cid2"

      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:client_join, client2_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      operation = {:client_leave, client2_id}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{
                    sources: %{
                      primary: %{deltas: [], revision_by_client_id: revision_by_client_id}
                    }
                  }
                }
              }, _} = Data.apply_operation(data, operation)

      assert revision_by_client_id == %{client1_id => 1}
    end
  end

  describe "apply_operation/2 given :update_user" do
    test "returns an error if the given user is not a client" do
      data = Data.new()

      operation = {:update_user, @cid, User.new()}
      assert :error = Data.apply_operation(data, operation)
    end

    test "updates users map" do
      %{id: user_id} = user = User.new()

      data =
        data_after_operations!([
          {:client_join, @cid, user}
        ])

      updated_user = %{user | name: "Jake Peralta"}
      operation = {:update_user, @cid, updated_user}

      assert {:ok, %{users_map: %{^user_id => ^updated_user}}, []} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :apply_cell_delta" do
    test "returns an error given invalid cell id" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()}
        ])

      operation = {:apply_cell_delta, @cid, "nonexistent", :primary, Delta.new(), 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given invalid revision" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, @cid, "c1", :primary, delta, 5}

      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given non-joined client pid and older revision" do
      client1_id = "cid1"

      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, @cid, "c1", :primary, delta, 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "updates cell source according to the given delta" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, @cid, "c1", :primary, delta, 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{source: "cats"}]}
                  ]
                },
                cell_infos: %{"c1" => %{sources: %{primary: %{revision: 1}}}}
              }, _actions} = Data.apply_operation(data, operation)
    end

    test "transforms the delta if the revision is not the most recent" do
      client1_id = "cid1"
      client2_id = "cid2"

      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:client_join, client2_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      delta2 = Delta.new() |> Delta.insert("tea")
      operation = {:apply_cell_delta, client2_id, "c1", :primary, delta2, 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{source: "catstea"}]}
                  ]
                },
                cell_infos: %{"c1" => %{sources: %{primary: %{revision: 2}}}}
              }, _} = Data.apply_operation(data, operation)
    end

    test "returns broadcast delta action with the transformed delta" do
      client1_id = "cid1"
      client2_id = "cid2"

      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:client_join, client2_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      delta2 = Delta.new() |> Delta.insert("tea")
      operation = {:apply_cell_delta, client2_id, "c1", :primary, delta2, 1}

      transformed_delta2 = Delta.new() |> Delta.retain(4) |> Delta.insert("tea")

      assert {:ok, _data, [{:broadcast_delta, ^client2_id, _cell, :primary, ^transformed_delta2}]} =
               Data.apply_operation(data, operation)
    end

    test "given single client, does not keep deltas" do
      client_id = "client1"

      data =
        data_after_operations!([
          {:client_join, client_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, client_id, "c1", :primary, delta, 1}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{sources: %{primary: %{deltas: []}}}}
              }, _} = Data.apply_operation(data, operation)
    end

    test "given multiple client, keeps the delta" do
      client1_id = "cid1"
      client2_id = "cid2"

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:client_join, client2_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, client1_id, "c1", :primary, delta, 1}

      assert {:ok,
              %{
                cell_infos: %{"c1" => %{sources: %{primary: %{deltas: [^delta]}}}}
              }, _} = Data.apply_operation(data, operation)
    end

    test "updates smart cell editor source given a secondary source delta" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 1, :smart, "c1", %{kind: "text"}},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:set_smart_cell_definitions, @cid, @smart_cell_definitions},
          {:smart_cell_started, @cid, "c1", Delta.new(), %{},
           %{language: "text", placement: :bottom, source: ""}}
        ])

      delta = Delta.new() |> Delta.insert("cats")
      operation = {:apply_cell_delta, @cid, "c1", :secondary, delta, 1}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{editor: %{source: "cats"}}]}
                  ]
                },
                cell_infos: %{"c1" => %{sources: %{secondary: %{revision: 1}}}}
              }, _actions} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :report_cell_revision" do
    test "returns an error given invalid cell id" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()}
        ])

      operation = {:report_cell_revision, @cid, "nonexistent", :primary, 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given non-joined client pid" do
      client1_id = "cid1"
      client2_id = "cid2"

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, Delta.new(insert: "cats"), 1}
        ])

      operation = {:report_cell_revision, client2_id, "c1", :primary, 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given invalid revision" do
      data =
        data_after_operations!([
          {:client_join, @cid, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      operation = {:report_cell_revision, @cid, "c1", :primary, 1}
      assert :error = Data.apply_operation(data, operation)
    end

    test "updates client entry in the revisions map and purges unnecessary deltas" do
      client1_id = "cid1"
      client2_id = "cid2"

      delta1 = Delta.new() |> Delta.insert("cats")

      data =
        data_after_operations!([
          {:client_join, client1_id, User.new()},
          {:client_join, client2_id, User.new()},
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:apply_cell_delta, client1_id, "c1", :primary, delta1, 1}
        ])

      operation = {:report_cell_revision, client2_id, "c1", :primary, 1}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{
                    sources: %{
                      primary: %{
                        deltas: [],
                        revision_by_client_id: %{^client1_id => 1, ^client2_id => 1}
                      }
                    }
                  }
                }
              }, _} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_cell_attributes" do
    test "returns an error given invalid cell id" do
      data = Data.new()

      operation = {:set_cell_attributes, @cid, "nonexistent", %{}}
      assert :error = Data.apply_operation(data, operation)
    end

    test "returns an error given an unknown attribute key" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      attrs = %{unknown: :value}
      operation = {:set_cell_attributes, @cid, "c1", attrs}

      assert :error = Data.apply_operation(data, operation)
    end

    test "updates cell with the given attributes" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}}
        ])

      attrs = %{disable_formatting: true, reevaluate_automatically: true}
      operation = {:set_cell_attributes, @cid, "c1", attrs}

      assert {:ok,
              %{
                notebook: %{
                  sections: [
                    %{cells: [%{disable_formatting: true, reevaluate_automatically: true}]}
                  ]
                }
              }, _} = Data.apply_operation(data, operation)
    end

    test "setting reevaluate_automatically on stale cell marks it for evaluation" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          # Evaluate cells
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          evaluate_cells_operations(["c1"])
        ])

      attrs = %{reevaluate_automatically: true}
      operation = {:set_cell_attributes, @cid, "c2", attrs}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{status: :ready}},
                  "c2" => %{eval: %{status: :evaluating}}
                }
              }, _} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_input_value" do
    test "returns an error given invalid input id" do
      data = Data.new()

      operation = {:set_input_value, @cid, "nonexistent", "stuff"}
      assert :error = Data.apply_operation(data, operation)
    end

    test "stores new input value" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta}
        ])

      operation = {:set_input_value, @cid, "i1", "stuff"}

      assert {:ok, %{input_values: %{"i1" => "stuff"}}, _} = Data.apply_operation(data, operation)
    end

    test "given input value change, marks evaluated bound cells and their dependants as stale" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          # Insert three evaluated cells and bind the second one to the input
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:insert_cell, @cid, "s1", 3, :code, "c4", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          evaluate_cells_operations(["c2", "c3", "c4"]),
          {:bind_input, @cid, "c3", "i1"}
        ])

      operation = {:set_input_value, @cid, "i1", "stuff"}

      assert {:ok,
              %{
                cell_infos: %{
                  "c2" => %{eval: %{validity: :evaluated}},
                  "c3" => %{eval: %{validity: :stale}},
                  "c4" => %{eval: %{validity: :stale}}
                }
              }, _} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_runtime" do
    test "updates data with the given runtime" do
      data = Data.new()

      runtime = connected_noop_runtime()
      operation = {:set_runtime, @cid, runtime}

      assert {:ok, %{runtime: ^runtime}, []} = Data.apply_operation(data, operation)
    end

    test "clears all statuses and the per-section queues" do
      data =
        data_after_operations!([
          # First section with evaluating and queued cells
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1", "c2"]},
          # Second section with evaluating and queued cells
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c3", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c4", %{}},
          {:queue_cells_evaluation, @cid, ["c3", "c4"]}
        ])

      runtime = connected_noop_runtime()
      operation = {:set_runtime, @cid, runtime}

      assert {:ok,
              %{
                cell_infos: %{
                  "c1" => %{eval: %{validity: :aborted, status: :ready}},
                  "c2" => %{eval: %{validity: :fresh, status: :ready}},
                  "c3" => %{eval: %{validity: :fresh, status: :ready}},
                  "c4" => %{eval: %{validity: :fresh, status: :ready}}
                },
                section_infos: %{
                  "s2" => %{evaluating_cell_id: nil, evaluation_queue: []},
                  "s1" => %{evaluating_cell_id: nil, evaluation_queue: []}
                }
              }, []} = Data.apply_operation(data, operation)
    end

    test "starts evaluation if there was no runtime before and there is now" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:queue_cells_evaluation, @cid, ["setup"]}
        ])

      runtime = connected_noop_runtime()
      operation = {:set_runtime, @cid, runtime}

      assert {:ok,
              %{
                cell_infos: %{
                  "setup" => %{eval: %{status: :evaluating}}
                },
                section_infos: %{
                  "setup-section" => %{evaluating_cell_id: "setup", evaluation_queue: []}
                }
              },
              [{:start_evaluation, %{id: "setup"}, %{id: "setup-section"}}]} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_smart_cell_definitions" do
    test "sets the definitions and starts dead cells with matching kinds" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :smart, "c1", %{kind: "text"}},
          {:set_runtime, @cid, connected_noop_runtime()}
        ])

      operation = {:set_smart_cell_definitions, @cid, @smart_cell_definitions}

      assert {:ok, %{cell_infos: %{"c1" => %{status: :starting}}}, _actions} =
               Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :set_file" do
    test "updates data with the given path" do
      data = Data.new()

      file = Livebook.FileSystem.File.local(p("/path/to/file.livemd"))
      operation = {:set_file, @cid, file}

      assert {:ok, %{file: ^file}, []} = Data.apply_operation(data, operation)
    end
  end

  describe "apply_operation/2 given :mark_as_not_dirty" do
    test "sets dirty flag to false" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"}
        ])

      operation = {:mark_as_not_dirty, @cid}

      assert {:ok, %{dirty: false}, []} = Data.apply_operation(data, operation)
    end
  end

  describe "bound_cells_with_section/2" do
    test "returns an empty list when an invalid input id is given" do
      data = Data.new()
      assert [] = Data.bound_cells_with_section(data, "nonexistent")
    end

    test "returns Code cells bound to the given input" do
      input = %{id: "i1", type: :text, label: "Text", default: "hey"}

      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:insert_cell, @cid, "s1", 4, :code, "c4", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"]),
          {:queue_cells_evaluation, @cid, ["c1"]},
          {:add_cell_evaluation_response, @cid, "c1", {:input, input}, @eval_meta},
          {:bind_input, @cid, "c2", "i1"},
          {:bind_input, @cid, "c4", "i1"}
        ])

      assert [{%{id: "c2"}, _}, {%{id: "c4"}, _}] = Data.bound_cells_with_section(data, "i1")
    end
  end

  @empty_digest :erlang.md5("")

  describe "cell_ids_for_full_evaluation/2" do
    test "includes changed cells with children" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"]),
          # Modify cell 2
          {:client_join, @cid, User.new()},
          {:apply_cell_delta, @cid, "c2", :primary, Delta.new() |> Delta.insert("cats"), 1}
        ])

      assert Data.cell_ids_for_full_evaluation(data, []) |> Enum.sort() == ["c2", "c3"]
    end

    test "includes fresh cells with children" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c3"]),
          # Insert a fresh cell between cell 1 and cell 3
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}}
        ])

      assert Data.cell_ids_for_full_evaluation(data, []) |> Enum.sort() == ["c2", "c3"]
    end

    test "includes stale cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          # Reevaluate cell 1
          evaluate_cells_operations(["c1"])
        ])

      assert Data.cell_ids_for_full_evaluation(data, []) |> Enum.sort() == ["c2"]
    end

    test "includes forced cells with children" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c3"])
        ])

      assert Data.cell_ids_for_full_evaluation(data, ["c2"]) |> Enum.sort() == ["c2", "c3"]
    end

    test "excludes evaluating and queued cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:insert_cell, @cid, "s1", 2, :code, "c3", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          {:queue_cells_evaluation, @cid, ["c1", "c2"]}
        ])

      assert Data.cell_ids_for_full_evaluation(data, []) |> Enum.sort() == ["c3"]
    end
  end

  describe "cell_ids_for_reevaluation/2" do
    test "does not include the setup cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup"])
        ])

      assert Data.cell_ids_for_reevaluation(data) == []
    end

    test "includes evaluated cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"])
        ])

      assert Data.cell_ids_for_reevaluation(data) |> Enum.sort() == ["c1", "c2"]
    end

    test "includes stale cells" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          # Reevaluate cell 1
          evaluate_cells_operations(["c1"])
        ])

      assert Data.cell_ids_for_reevaluation(data) |> Enum.sort() == ["c1", "c2"]
    end

    test "stops reevaluation on the first fresh cell" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_cell, @cid, "s1", 1, :code, "c2", %{}},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2"]),
          # Reevaluate cell 1
          {:insert_cell, @cid, "s1", 1, :code, "c3", %{}}
        ])

      assert Data.cell_ids_for_reevaluation(data) |> Enum.sort() == ["c1"]
    end

    test "considers each branch separately" do
      data =
        data_after_operations!([
          {:insert_section, @cid, 0, "s1"},
          {:insert_cell, @cid, "s1", 0, :code, "c1", %{}},
          {:insert_section, @cid, 1, "s2"},
          {:insert_cell, @cid, "s2", 0, :code, "c2", %{}},
          {:insert_cell, @cid, "s2", 1, :code, "c3", %{}},
          {:insert_section, @cid, 2, "s3"},
          {:insert_cell, @cid, "s3", 0, :code, "c4", %{}},
          {:set_section_parent, @cid, "s2", "s1"},
          {:set_runtime, @cid, connected_noop_runtime()},
          evaluate_cells_operations(["setup", "c1", "c2", "c4"])
        ])

      assert Data.cell_ids_for_reevaluation(data) |> Enum.sort() == ["c1", "c2", "c4"]
    end
  end

  defp evaluate_cells_operations(cell_ids) do
    [
      {:queue_cells_evaluation, @cid, cell_ids},
      for(
        cell_id <- cell_ids,
        do: [
          {:evaluation_started, @cid, cell_id, @empty_digest},
          {:add_cell_evaluation_response, @cid, cell_id, @eval_resp, @eval_meta}
        ]
      )
    ]
  end

  defp connected_noop_runtime() do
    {:ok, runtime} = Livebook.Runtime.NoopRuntime.new() |> Livebook.Runtime.connect()
    runtime
  end
end
