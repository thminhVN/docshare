defmodule DocshareWeb.UserLoginLive do
  use DocshareWeb, :live_view

  alias DocshareWeb.UserAuth

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in to account
        <:subtitle>
          Don't have an account?
          <.link navigate={@register_path} class="font-semibold text-brand hover:underline">
            Sign up
          </.link>
          for an account now.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="login_form" action={@login_path} phx-update="ignore">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
          <.link href={~p"/users/reset_password"} class="text-sm font-semibold">
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Logging in..." class="w-full">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(params, session, socket) do
    return_to =
      UserAuth.local_return_to(params["return_to"]) ||
        UserAuth.local_return_to(session["user_return_to"])

    invited_email = UserAuth.invited_email(params, return_to)
    email = Phoenix.Flash.get(socket.assigns.flash, :email) || invited_email
    form = to_form(%{"email" => email}, as: "user")

    socket =
      assign(socket,
        form: form,
        login_path: auth_path(~p"/users/log_in", return_to, invited_email),
        register_path: auth_path(~p"/users/register", return_to, invited_email)
      )

    {:ok, socket, temporary_assigns: [form: form]}
  end

  defp auth_path(path, return_to, invited_email) do
    query =
      [return_to: return_to, invited_email: invited_email]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case query do
      [] -> path
      query -> path <> "?" <> URI.encode_query(query)
    end
  end
end
