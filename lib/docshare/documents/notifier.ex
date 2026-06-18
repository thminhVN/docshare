defmodule Docshare.Documents.Notifier do
  @moduledoc "Sends sharing-invitation emails via Swoosh."

  import Swoosh.Email
  alias Docshare.Mailer

  def deliver_invitation(collaborator, document, inviter) do
    url = DocshareWeb.Endpoint.url() <> "/docs/#{document.token}"

    email =
      new()
      |> to(collaborator.email)
      |> from(mail_from())
      |> subject("#{inviter.email} shared a document with you: #{document.title}")
      |> text_body("""
      Hi,

      #{inviter.email} invited you to comment on "#{document.title}".

      Open it here: #{url}

      If you don't have an account yet, register with this email address
      (#{collaborator.email}) to get access.
      """)
      |> html_body(html_invitation(collaborator, document, inviter, url))

    with {:ok, _meta} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  # Email-safe HTML (tables + inline styles): a centered card with a coloured
  # header, the document title, and a call-to-action button.
  defp html_invitation(collaborator, document, inviter, url) do
    title = html_escape(document.title)
    inviter_email = html_escape(inviter.email)
    invitee_email = html_escape(collaborator.email)

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
              <!-- Card header -->
              <tr>
                <td style="background-color:#4f46e5; padding:20px 28px;">
                  <span style="font-size:18px; font-weight:700; letter-spacing:-0.01em; color:#ffffff;">DocShare</span>
                </td>
              </tr>
              <!-- Card body -->
              <tr>
                <td style="padding:28px;">
                  <h1 style="margin:0 0 6px 0; font-size:20px; font-weight:700; color:#18181b;">#{title}</h1>
                  <p style="margin:0 0 20px 0; font-size:14px; line-height:22px; color:#52525b;">
                    <strong style="color:#18181b;">#{inviter_email}</strong> invited you to view and comment on this document.
                  </p>
                  <table role="presentation" cellpadding="0" cellspacing="0">
                    <tr>
                      <td align="center" style="border-radius:8px; background-color:#4f46e5;">
                        <a href="#{url}" target="_blank"
                           style="display:inline-block; padding:12px 24px; font-size:14px; font-weight:600; color:#ffffff; text-decoration:none; border-radius:8px;">
                          Open document
                        </a>
                      </td>
                    </tr>
                  </table>
                  <p style="margin:20px 0 0 0; font-size:12px; line-height:18px; color:#71717a;">
                    If the button doesn't work, copy and paste this link:<br />
                    <a href="#{url}" target="_blank" style="color:#4f46e5; word-break:break-all;">#{url}</a>
                  </p>
                  <p style="margin:16px 0 0 0; padding-top:16px; border-top:1px solid #f4f4f5; font-size:12px; line-height:18px; color:#71717a;">
                    No account yet? Register with <strong style="color:#3f3f46;">#{invitee_email}</strong> to get access.
                  </p>
                </td>
              </tr>
              <!-- Card footer -->
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

  defp html_escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  # Sender address. Resend requires this to be a verified domain (or the shared
  # `onboarding@resend.dev` sandbox sender). Override with the MAIL_FROM env var,
  # e.g. MAIL_FROM="DocShare <noreply@gatetroy.com>".
  defp mail_from do
    case Application.get_env(:docshare, :mail_from) do
      {_name, _addr} = tuple -> tuple
      address when is_binary(address) -> parse_from(address)
      _ -> {"DocShare", "onboarding@resend.dev"}
    end
  end

  # Accepts either a bare "user@example.com" or a "Name <user@example.com>" string.
  defp parse_from(address) do
    case Regex.run(~r/^\s*(.*?)\s*<\s*(.+?)\s*>\s*$/, address) do
      [_, name, addr] -> {name, addr}
      _ -> {"DocShare", String.trim(address)}
    end
  end
end
