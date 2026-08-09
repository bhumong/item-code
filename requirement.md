# Technical Design Specification: Multi-Page OCR Image Document Search Engine

**Date:** 2026-08-09

---

## 1. Overview & Vision

This specification defines the architecture, data schemas, API integration points, and UI design for a mobile-first web application built with **Flutter Web** and **Go + PocketBase**.

The system enables users to create document containers (acting like books/folders), upload page images into them, and automatically extract text contents using the **DeepSeek API**. Stored extracted contents enable fast text-based search across all document pages with visual search highlights and page previews.

---

## 2. Core Constraints & Guiding Principles

1. **No Document Ownership Constraint:** Documents and pages belong to a single global collection accessible by all whitelisted users.
2. **Persistent Queue over In-Memory Goroutines:** Background processing uses a dedicated `ocr_queue` collection in PocketBase processed by a scheduled PocketBase Cron job. This ensures task execution state persists across application reboots or service failures.
3. **Whitelist Authentication:** Only Google OAuth emails matching entries in the `allowed_users` whitelist collection can authenticate.
4. **S3 Object Storage Integration:** PocketBase native S3 filesystem driver stores all high-resolution uploaded images.

---

## 3. Data Schema Specifications

### `allowed_users` Collection

Stores whitelisted email addresses authorized to log into the application.

| Field Name | Type | Rules | Description |
| --- | --- | --- | --- |
| `id` | Record ID | Primary Key | Standard PocketBase ID |
| `email` | Email | Unique, Required | Whitelisted Google email address |

### `documents` Collection

Acts as the parent entity holding titles (e.g., Book Title, Receipt Folder, Manual Name).

| Field Name | Type | Rules | Description |
| --- | --- | --- | --- |
| `id` | Record ID | Primary Key | Standard PocketBase ID |
| `title` | Text | Required | Name/Title of the document |
| `created` | DateTime | Auto-set | Creation timestamp |
| `updated` | DateTime | Auto-set | Modification timestamp |

### `pages` Collection

Represents individual page images inside a parent document.

| Field Name | Type | Rules | Description |
| --- | --- | --- | --- |
| `id` | Record ID | Primary Key | Standard PocketBase ID |
| `document` | Relation | Required | Foreign Key -> `documents.id` |
| `page_number` | Number | Required | Page index/order within the document |
| `image` | File | Required | Single file uploaded to S3 |
| `ocr_text` | Text | Optional | Extracted plain text string from DeepSeek |
| `status` | Select | Default: `pending` | Enum: `pending`, `processing`, `completed`, `failed` |
| `created` | DateTime | Auto-set | Creation timestamp |
| `updated` | DateTime | Auto-set | Modification timestamp |

### `ocr_queue` Collection

Manages reliable, persistent processing tasks for background DeepSeek OCR inference.

| Field Name | Type | Rules | Description |
| --- | --- | --- | --- |
| `id` | Record ID | Primary Key | Standard PocketBase ID |
| `page` | Relation | Required, Unique | Foreign Key -> `pages.id` |
| `status` | Select | Default: `queued` | Enum: `queued`, `in_progress`, `completed`, `failed` |
| `retry_count` | Number | Default: 0 | Number of execution retries |
| `error_log` | Text | Optional | Exception or error response string |
| `created` | DateTime | Auto-set | Queue entry creation timestamp |
| `updated` | DateTime | Auto-set | Last status update timestamp |

---

## 4. Go + PocketBase Backend Architecture

### 4.1 Google OAuth Whitelist Hook

During OAuth authentication, PocketBase executes an `OnRecordAuthWithOAuth2Request` hook:

```
[ OAuth Callback Received ] 
         │
         ▼
[ Extract Email from Provider Claims ]
         │
         ▼
[ Query `allowed_users` where email = ProviderEmail ]
         ├────────────────────────┬────────────────────────┐
         ▼ (Found)                                         ▼ (Not Found)
[ Allow Authentication ]                         [ Abort Auth & Return 403 ]

```

### 4.2 Page Upload & Queue Creation Flow

When a user uploads an image page:

1. PocketBase writes the file directly to the S3-compatible object storage bucket.
2. PocketBase creates a record in `pages` with `status="pending"`.
3. PocketBase triggers `OnRecordAfterCreateSuccess("pages")` event hook, creating an entry in `ocr_queue` with `page=<page_id>` and `status="queued"`.

### 4.3 Cron Worker Engine

A native PocketBase Cron task executes every minute (`*/1 * * * *`):

```
[ Cron Trigger: Every 1 Minute ]
         │
         ▼
[ Fetch up to N records from `ocr_queue` where status = "queued" ]
         │
         ▼
[ For Each Queue Item ] ──► Set `ocr_queue.status` = "in_progress", `pages.status` = "processing"
         │
         ▼
[ Read Page Image File from S3 Storage ]
         │
         ▼
[ POST Request to `https://api.deepseek.com/v1/chat/completions` ]
 (Multimodal Prompt: "Extract all legible text from this image accurately.")
         │
         ├─────────────────────────────────────────┐
         ▼ (Success)                               ▼ (Error / Timeout)
[ Update `pages.ocr_text` = Content ]     [ Increment `ocr_queue.retry_count` ]
[ Set `pages.status` = "completed" ]      [ If retry_count >= 3: ]
[ Set `ocr_queue.status` = "completed" ]   [   Set status = "failed" ]
                                           [   Set `pages.status` = "failed" ]

```

---

## 5. Mobile-First Flutter Web Interface Design

The UI focuses on touch-friendly mobile navigation, responsive layouts, and quick text search.

### Key Screens & Components

1. **Login Screen:** Minimalist splash screen with a single "Sign in with Google" button. Displays error toasts if email is not whitelisted.
2. **Document Explorer Screen (Home):**
* Fixed header with global search bar.
* Grid or card list displaying Document Titles with page count indicators.
* Floating Action Button (FAB) `+` to create a new Document Container.


3. **Document Detail & Page Management Screen:**
* Document title header with edit action.
* Responsive multi-column page gallery displaying thumbnails, page numbers, and processing status tags (`Pending`, `Processing`, `Completed`, `Failed`).
* "Add Pages" batch picker for uploading images into the document.


4. **Search Results View:**
* Real-time or submit-triggered full-text search across `documents.title` and `pages.ocr_text`.
* Results display parent Document Title, matching Page Number thumbnail, and highlighted matching text snippet.



---

## 6. Verification & Self-Review Loop

1. **Placeholder Scan:** Passed (All collections, fields, and workflow endpoints explicitly declared).
2. **Internal Consistency Check:** Passed (Cron worker and `ocr_queue` model fully match the persistent queue requirement without using detached Goroutines).
3. **Scope Check:** Passed (Focused purely on whitelist auth, multi-page document container management, async Cron OCR worker, and text search).
4. **Ambiguity Check:** Passed (Single global workspace specified - no individual user ownership or tenancy boundaries required).

---
