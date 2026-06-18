defmodule DocshareWeb.UserRegistrationLiveTest do
  use DocshareWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Docshare.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "preserves return_to in login action and login link", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register?return_to=/docs/invite-token")

      assert html =~
               ~s(action="/users/log_in?return_to=%2Fdocs%2Finvite-token&amp;_action=registered")

      assert html =~ ~s(href="/users/log_in?return_to=%2Fdocs%2Finvite-token")
    end

    test "prefills invited email from return_to document URL", %{conn: conn} do
      return_to = "/docs/invite-token?invited_email=friend@example.com"
      {:ok, _lv, html} = live(conn, ~p"/users/register?return_to=#{return_to}")

      assert html =~ ~s(value="friend@example.com")
      assert html =~ "invited_email=friend%40example.com"
      assert html =~ "_action=registered"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, "/")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces", "password" => "short"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
      assert result =~ "should be at least 6 character"
    end
  end

  describe "register user" do
    test "creates account and logs the user in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/")
      response = html_response(conn, 200)
      assert response =~ email
      assert response =~ "Settings"
      assert response =~ "Log out"
    end

    test "creates account and redirects to return_to", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register?return_to=/docs/invite-token")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == "/docs/invite-token"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email, "password" => "valid_password"}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Log in"
    end
  end
end
