defmodule DocshareWeb.UserLoginLiveTest do
  use DocshareWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Docshare.AccountsFixtures

  describe "Log in page" do
    test "renders log in page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ "Log in"
      assert html =~ "Register"
      assert html =~ "Forgot your password?"
    end

    test "preserves return_to in form action and register link", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in?return_to=/docs/invite-token")

      assert html =~ ~s(action="/users/log_in?return_to=%2Fdocs%2Finvite-token")
      assert html =~ ~s(href="/users/register?return_to=%2Fdocs%2Finvite-token")
    end

    test "prefills invited email from return_to document URL", %{conn: conn} do
      return_to = "/docs/invite-token?invited_email=friend@example.com"
      {:ok, _lv, html} = live(conn, ~p"/users/log_in?return_to=#{return_to}")

      assert html =~ ~s(value="friend@example.com")
      assert html =~ "invited_email=friend%40example.com"
      assert html =~ ~s(href="/users/register?)
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/log_in")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end
  end

  describe "user login" do
    test "redirects if user login with valid credentials", %{conn: conn} do
      password = "123456789abcd"
      user = user_fixture(%{password: password})

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form", user: %{email: user.email, password: password, remember_me: true})

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if there are no valid credentials", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form",
          user: %{email: "test@email.com", password: "123456", remember_me: true}
        )

      conn = submit_form(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"

      assert redirected_to(conn) == "/users/log_in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end

    test "redirects to forgot password page when the Forgot Password button is clicked", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, conn} =
        lv
        |> element("main a", "Forgot your password?")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/reset_password")

      assert conn.resp_body =~ "Forgot your password?"
    end
  end
end
