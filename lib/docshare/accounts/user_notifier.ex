defmodule Docshare.Accounts.UserNotifier do
  import Swoosh.Email

  alias Docshare.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, text_body, html_body \\ nil) do
    email =
      new()
      |> to(recipient)
      |> from(mail_from())
      |> subject(subject)
      |> text_body(text_body)
      |> maybe_html_body(html_body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp maybe_html_body(email, nil), do: email
  defp maybe_html_body(email, html_body), do: html_body(email, html_body)

  defp mail_from do
    case Application.get_env(:docshare, :mail_from) do
      {_name, _addr} = tuple -> tuple
      address when is_binary(address) -> parse_from(address)
      _ -> {"DocShare", "noreply@gatetroy.com"}
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
    deliver(
      user.email,
      "Confirmation instructions",
      confirmation_text(user, url),
      confirmation_html(user, url)
    )
  end

  defp confirmation_text(user, url) do
    """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """
  end

  defp confirmation_html(user, url) do
    email = html_escape(user.email)
    escaped_url = html_escape(url)

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body style="margin:0; padding:0; background-color:#f4f4f5;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f5;">
          <tr>
            <td align="center" style="padding:32px 16px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px; background-color:#ffffff; border:1px solid #e4e4e7; border-radius:12px; overflow:hidden; font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
              <tr>
                <td style="background-color:#4f46e5; padding:20px 28px;">
                  <span style="font-size:18px; font-weight:700; letter-spacing:-0.01em; color:#ffffff;">DocShare</span>
                </td>
              </tr>
              <tr>
                <td style="padding:28px;">
                  <h1 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#18181b;">Confirm your account</h1>
                  <p style="margin:0 0 20px 0; font-size:14px; line-height:22px; color:#52525b;">
                    Hi <strong style="color:#18181b;">#{email}</strong>, confirm your DocShare account to start reviewing shared documents.
                  </p>
                  <table role="presentation" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center" style="border-radius:8px; background-color:#4f46e5;">
                        <a href="#{escaped_url}" target="_blank"
                           style="display:inline-block; padding:12px 24px; font-size:14px; font-weight:600; color:#ffffff; text-decoration:none; border-radius:8px;">
                          Confirm account
                        </a>
                      </td>
                    </tr>
                  </table>
                  <p style="margin:20px 0 0 0; font-size:12px; line-height:18px; color:#71717a;">
                    If the button doesn't work, copy and paste this link:<br />
                    <a href="#{escaped_url}" target="_blank" style="color:#4f46e5; word-break:break-all;">#{escaped_url}</a>
                  </p>
                  <p style="margin:16px 0 0 0; padding-top:16px; border-top:1px solid #f4f4f5; font-size:12px; line-height:18px; color:#71717a;">
                    If you didn't create a DocShare account, you can safely ignore this email.
                  </p>
                </td>
              </tr>
              <tr>
                <td style="padding:16px 28px; background-color:#fafafa; border-top:1px solid #f4f4f5; text-align:center;">
                  <span style="font-size:12px; color:#a1a1aa;">Made by
                    <a href="https://gatetroy.com" target="_blank" style="color:#4f46e5; font-weight:600; text-decoration:none;">gatetroy.com</a>
                  </span>
                </td>
              </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
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

  defp html_escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
