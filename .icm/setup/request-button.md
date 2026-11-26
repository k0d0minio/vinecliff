# Setup — the request button

A client asks for a change from the app itself: the button opens a form, and the request
goes to the store of this repo with a capture of the page (`.icm/_system/features/requests.md`).

## The code: one import, one route (a session can do this part)
The root layout (`app/layout.tsx` or `src/app/layout.tsx`) gets one import and one element
in `<body>`. Use the relative path from the layout to `.icm/` (`../.icm` from `app/`,
`../../.icm` from `src/app/`):

```tsx
import { RequestButton } from "../../.icm/_system/request-button/RequestButton";
// in <body>, after {children}:
<RequestButton />
```

The route is one new file, `app/api/baxter-request/route.ts` (or below `src/`):

```ts
export { POST } from "../../../../.icm/_system/request-button/route";
```

No other file changes. The prop `user` (`signedIn`, `role`, `id`) adds the user to the
capture when the layout knows the user. The id leaves the server only as a hash.

## The env values (the operator)
Set these in Vercel for the UAT environment. A local dev server shows the button with no
value.

- [ ] `BAXTER_REQUEST_ENV` = `uat` on UAT. Not set on production: the button does not show.
      Production only with `production` and `BAXTER_REQUEST_PRODUCTION` = `on`.
- [ ] `BAXTER_REQUEST_LINEAR_API_KEY`: a Linear API key of the client's workspace that can
      create issues and labels in the team `requests.linear_team` of `.icm/project.json`.

Each value is a secret of the deployment. Never put one in the code or in this repo.
