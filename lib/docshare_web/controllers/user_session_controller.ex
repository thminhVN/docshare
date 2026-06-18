defmodule DocshareWeb.UserSessionController do
  use DocshareWeb, :controller

  alias Docshare.Accounts
  alias DocshareWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    conn
    |> maybe_put_user_return_to(params)
    |> create(params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    conn
    |> maybe_put_user_return_to(params)
    |> create(params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params} = params, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: login_path(params))
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp maybe_put_user_return_to(conn, %{"return_to" => return_to}) do
    if return_to = UserAuth.local_return_to(return_to) do
      put_session(conn, :user_return_to, return_to)
    else
      conn
    end
  end

  defp maybe_put_user_return_to(conn, _params), do: conn

  defp login_path(params) do
    query =
      []
      |> maybe_put_query("return_to", UserAuth.local_return_to(params["return_to"]))
      |> maybe_put_query("invited_email", params["invited_email"])

    case query do
      [] -> ~p"/users/log_in"
      query -> ~p"/users/log_in?#{query}"
    end
  end

  defp maybe_put_query(query, _key, nil), do: query
  defp maybe_put_query(query, _key, ""), do: query
  defp maybe_put_query(query, key, value), do: [{key, value} | query]
end
