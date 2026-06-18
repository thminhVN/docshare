defmodule DocshareWeb.UserRegistrationLive do
  use DocshareWeb, :live_view

  alias Docshare.Accounts
  alias Docshare.Accounts.User
  alias DocshareWeb.UserAuth

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already registered?
          <.link navigate={@login_path} class="font-semibold text-brand hover:underline">
            Log in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={@registration_login_path}
        method="post"
      >
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">Create an account</.button>
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
    changeset = Accounts.change_user_registration(%User{email: invited_email})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(
        login_path: auth_path(~p"/users/log_in", return_to, invited_email),
        registration_login_path:
          auth_path(~p"/users/log_in", return_to, invited_email, [{"_action", "registered"}])
      )
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/users/confirm/#{&1}")
        )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp auth_path(path, return_to, invited_email),
    do: auth_path(path, return_to, invited_email, [])

  defp auth_path(path, return_to, invited_email, query) do
    query =
      query
      |> maybe_put_query("return_to", return_to)
      |> maybe_put_query("invited_email", invited_email)

    path_with_query(path, query)
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, key, value), do: [{key, value} | query]

  defp path_with_query(path, []), do: path
  defp path_with_query(path, query), do: path <> "?" <> URI.encode_query(query)
end
