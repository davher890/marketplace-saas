import nodemailer, { type Transporter } from 'nodemailer';

// Sending email. This is the only file that knows how: plain SMTP, today with
// the shop's Gmail account (an app password, the same one Supabase Auth uses
// for its own emails). Moving to Brevo, IONOS, Resend... is a matter of the
// SMTP_* variables, or of rewriting [sendEmail].
//
//   SMTP_HOST      smtp.gmail.com
//   SMTP_PORT      465 (TLS) or 587 (STARTTLS)
//   SMTP_USER      donagalletashop@gmail.com
//   SMTP_PASSWORD  the app password (secret)
//   EMAIL_FROM     optional, defaults to "Doña Galleta <SMTP_USER>"
//
// Without SMTP_HOST nothing is sent (and nothing fails).

export interface Email {
  to: string | string[];
  subject: string;
  html: string;
  text: string;
  /** Where replies go; defaults to the sender. */
  replyTo?: string;
}

interface SmtpConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  from: string;
}

function smtpConfig(): SmtpConfig | null {
  const host = process.env.SMTP_HOST;
  if (!host) return null;
  const user = process.env.SMTP_USER ?? '';
  const password = process.env.SMTP_PASSWORD ?? '';
  if (!user || !password) throw new Error('SMTP_HOST is set but SMTP_USER or SMTP_PASSWORD is missing');
  return {
    host,
    port: Number(process.env.SMTP_PORT ?? 465),
    user,
    password,
    from: process.env.EMAIL_FROM || `"Doña Galleta" <${user}>`,
  };
}

export function emailConfigured(): boolean {
  return Boolean(process.env.SMTP_HOST);
}

// Reused while the function instance stays warm.
let transporter: Transporter | null = null;

function transport(config: SmtpConfig): Transporter {
  transporter ??= nodemailer.createTransport({
    host: config.host,
    port: config.port,
    secure: config.port === 465,
    auth: { user: config.user, pass: config.password },
    // A slow mail server must not hold the request (and the order) for long.
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 15_000,
  });
  return transporter;
}

/**
 * Sends one email. Never throws: an email that can't be sent is logged and
 * must not fail the request that caused it (an order, a status change).
 * Returns whether it was sent.
 */
export async function sendEmail(email: Email): Promise<boolean> {
  const recipients = (Array.isArray(email.to) ? email.to : [email.to]).filter(Boolean);
  if (recipients.length === 0) return false;
  try {
    const config = smtpConfig();
    if (!config) return false;
    await transport(config).sendMail({
      from: config.from,
      to: recipients,
      replyTo: email.replyTo,
      subject: email.subject,
      html: email.html,
      text: email.text,
    });
    return true;
  } catch (error) {
    console.error(`Could not send "${email.subject}" to ${recipients.join(', ')}`, error);
    return false;
  }
}
