defmodule Docshare.Accounts.UserNotifier do
  import Swoosh.Email

  alias Docshare.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(mail_from())
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp mail_from do
    case Application.get_env(:docshare, :mail_from) do
      {_name, _addr} = tuple -> tuple
      address when is_binary(address) -> parse_from(address)
      _ -> {"DocShare", "onboarding@resend.dev"}
    end
  end

  defp parse_from(address) do
    case Regex.run(~r/^\s*(.*?)\s*<\s*(.+?)\s*>\s*$/, address) do
      [_, "", email] -> email
      [_, name, email] -> {name, email}
      _ -> address
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    ==============================

    Hi #{user.email},

    You can create a new password by visiting the URL below:

    #{url}

    This link expires in 24 hours.

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
