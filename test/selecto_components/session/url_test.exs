defmodule SelectoComponents.Session.URLTest do
  use ExUnit.Case, async: true

  alias SelectoComponents.Session.URL

  test "query parameters remain enabled by default" do
    assert URL.query_params_enabled?(socket(%{}))
  end

  test "atom and string domain policies disable query parameters" do
    refute URL.query_params_enabled?(socket(%{components: %{query_params: false}}))

    refute URL.query_params_enabled?(socket(%{"components" => %{"query_params" => false}}))
  end

  test "malformed authored private policy fails closed" do
    refute URL.query_params_enabled?(socket(%{components: %{query_params: "false"}}))
    refute URL.query_params_enabled?(socket(%{components: "private"}))
  end

  test "private state transitions contain only the route path" do
    updated =
      URL.state_to_url(
        %{"filters" => %{"k0" => %{"value" => "patient-123"}}},
        socket(%{components: %{query_params: false}})
      )

    assert {:live, :patch, %{to: "/orders"}} = updated.redirected
    refute inspect(updated.redirected) =~ "patient-123"
  end

  test "query-library selection is part of shareable URL state" do
    params =
      URL.view_config_to_params(%{
        view_mode: "detail",
        views: %{},
        query_library: %{
          view: "active_summaries",
          segments: ["named_project"],
          parameters: %{"minimum" => "3"}
        }
      })

    assert params["query_library"] == %{
             "view" => "active_summaries",
             "segments" => ["named_project"],
             "parameters" => %{"minimum" => "3"}
           }
  end

  defp socket(domain) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        my_path: "/orders",
        params: %{},
        selecto: %{domain: domain}
      }
    }
  end
end
