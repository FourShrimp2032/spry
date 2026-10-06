# Spry — Privacy policy

Last updated: 6 October 2026

Spry ("the app") is a meetings workspace built as a student project for a university cloud-computing course. It is available at https://d310vkwtz8a1f0.cloudfront.net. This policy explains what data the app collects, how it is used, where it is stored, and how you can have it deleted.

## 1. Data we collect

**When you create an account with an email and password:**
- your email address and whether it has been verified;
- your password, which is stored and checked only by Amazon Cognito (the app itself never receives or stores it).

**When you sign in with Google**, the app requests only the `openid`, `email` and `profile` scopes and receives from Google:
- your email address and whether Google has verified it;
- your name;
- a unique Google account identifier.

**When you use the app:**
- meetings you create: title, start and end time, and number of attendees.

The app does not request access to your Google contacts, calendar, Drive, Gmail or any other Google data.

## 2. How we use the data

- Your email address is used to sign you in and to show who is signed in, in the page header.
- Your email address is used by Amazon Cognito to send a confirmation code when you sign up, and a reset code if you forget your password.
- Meetings data is used only to display your meetings in the app.

We do not use your data for advertising, profiling or analytics, and we do not use it to train machine-learning models.

## 3. Google user data

The app's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Google user data is used only to sign you in and to show who is signed in. It is not sold, not transferred to third parties, and not read by humans except to delete an account at your request or where required by law.

## 4. Sharing

We do not sell, rent or share personal data with anyone. The data is processed only by Amazon Web Services, which hosts the app (Amazon Cognito for accounts, Amazon RDS for meetings, Amazon CloudFront for the website).

## 5. Storage and security

- Account data is stored in Amazon Cognito in the AWS us-east-1 region (United States).
- Meetings are stored in an encrypted Amazon RDS database in the AWS eu-north-1 region (Stockholm, Sweden).
- All traffic to the app uses HTTPS. Sign-in uses OAuth 2.0 with PKCE; the app never sees your Google password.

## 6. Cookies and local storage

The app stores your sign-in session in your browser's session storage so that you stay signed in while the tab is open. It uses no tracking or advertising cookies.

## 7. Retention and deletion

The app, including all accounts and data, will be deleted when the course ends. You can sign out at any time. To have your account and data deleted sooner, open an issue at https://github.com/FourShrimp2032/spry/issues; it will be deleted within 7 days. You can also remove the app's access to your Google account at https://myaccount.google.com/permissions.

## 8. Children

The app is not intended for children under 16.

## 9. Changes

Changes to this policy are published on this page, with a new "Last updated" date.

## 10. Contact

Questions about this policy: https://github.com/FourShrimp2032/spry/issues
