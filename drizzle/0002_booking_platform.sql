CREATE TYPE "public"."booking_source" AS ENUM('website', 'phone', 'email', 'admin');--> statement-breakpoint
CREATE TYPE "public"."booking_status" AS ENUM('pending', 'approved', 'declined', 'cancelled');--> statement-breakpoint
CREATE TYPE "public"."enquiry_status" AS ENUM('new', 'replied', 'converted', 'archived');--> statement-breakpoint
CREATE TYPE "public"."payment_status" AS ENUM('unpaid', 'deposit_paid', 'paid', 'refunded');--> statement-breakpoint
CREATE TABLE "blackouts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"space_id" uuid,
	"start_date" date NOT NULL,
	"end_date" date NOT NULL,
	"reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "bookings" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"reference" text NOT NULL,
	"space_id" uuid NOT NULL,
	"guest_id" uuid NOT NULL,
	"status" "booking_status" DEFAULT 'pending' NOT NULL,
	"start_date" date NOT NULL,
	"end_date" date NOT NULL,
	"party_size" integer NOT NULL,
	"event_type" text,
	"guest_message" text,
	"quoted_total_cents" integer NOT NULL,
	"final_total_cents" integer,
	"deposit_cents" integer,
	"payment_status" "payment_status" DEFAULT 'unpaid' NOT NULL,
	"blocks_estate" boolean DEFAULT false NOT NULL,
	"source" "booking_source" DEFAULT 'website' NOT NULL,
	"manage_token" text NOT NULL,
	"decision_note" text,
	"admin_notes" text,
	"cancel_requested_at" timestamp with time zone,
	"decided_at" timestamp with time zone,
	"cancelled_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "bookings_reference_unique" UNIQUE("reference"),
	CONSTRAINT "bookings_manage_token_unique" UNIQUE("manage_token")
);
--> statement-breakpoint
CREATE TABLE "enquiries" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"phone" text,
	"space_id" uuid,
	"message" text NOT NULL,
	"status" "enquiry_status" DEFAULT 'new' NOT NULL,
	"booking_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "guests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"first_name" text NOT NULL,
	"last_name" text NOT NULL,
	"phone" text,
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "guests_email_unique" UNIQUE("email")
);
--> statement-breakpoint
CREATE TABLE "settings" (
	"key" text PRIMARY KEY NOT NULL,
	"value" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "spaces" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"slug" text NOT NULL,
	"name" text NOT NULL,
	"kind" text NOT NULL,
	"age" text NOT NULL,
	"blurb" text NOT NULL,
	"description" text NOT NULL,
	"image" text NOT NULL,
	"features" text[] DEFAULT '{}'::text[] NOT NULL,
	"is_event" boolean DEFAULT false NOT NULL,
	"blocks_estate" boolean DEFAULT false NOT NULL,
	"nightly_rate_cents" integer NOT NULL,
	"weekly_rate_cents" integer,
	"cleaning_fee_cents" integer DEFAULT 0 NOT NULL,
	"min_nights" integer DEFAULT 1 NOT NULL,
	"max_guests" integer NOT NULL,
	"buffer_days" integer DEFAULT 1 NOT NULL,
	"min_lead_days" integer DEFAULT 2 NOT NULL,
	"max_horizon_months" integer DEFAULT 18 NOT NULL,
	"ical_token" text DEFAULT md5(gen_random_uuid()::text || gen_random_uuid()::text) NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "spaces_slug_unique" UNIQUE("slug"),
	CONSTRAINT "spaces_ical_token_unique" UNIQUE("ical_token")
);
--> statement-breakpoint
ALTER TABLE "blackouts" ADD CONSTRAINT "blackouts_space_id_spaces_id_fk" FOREIGN KEY ("space_id") REFERENCES "public"."spaces"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_space_id_spaces_id_fk" FOREIGN KEY ("space_id") REFERENCES "public"."spaces"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bookings" ADD CONSTRAINT "bookings_guest_id_guests_id_fk" FOREIGN KEY ("guest_id") REFERENCES "public"."guests"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "enquiries" ADD CONSTRAINT "enquiries_space_id_spaces_id_fk" FOREIGN KEY ("space_id") REFERENCES "public"."spaces"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "enquiries" ADD CONSTRAINT "enquiries_booking_id_bookings_id_fk" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "blackouts_space_dates_idx" ON "blackouts" USING btree ("space_id","start_date");--> statement-breakpoint
CREATE INDEX "bookings_space_dates_idx" ON "bookings" USING btree ("space_id","start_date");--> statement-breakpoint
CREATE INDEX "bookings_status_idx" ON "bookings" USING btree ("status");--> statement-breakpoint
CREATE INDEX "bookings_guest_idx" ON "bookings" USING btree ("guest_id");--> statement-breakpoint
CREATE INDEX "enquiries_status_idx" ON "enquiries" USING btree ("status");--> statement-breakpoint
CREATE INDEX "spaces_sort_idx" ON "spaces" USING btree ("sort_order");