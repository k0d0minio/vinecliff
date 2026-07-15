import Image from "next/image";
import { gallery } from "@/lib/site";
import { PageHeader } from "../components/page-shell";

export const metadata = { title: "Gallery" };

export default function GalleryPage() {
  return (
    <div className="space-y-8">
      <PageHeader
        title="Gallery"
        description="Photography featured on the public website. Uploading and reordering will be enabled here soon."
      />

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {gallery.map((photo) => (
          <figure
            key={photo.src}
            className="group relative aspect-4/3 overflow-hidden rounded-2xl border border-pine-100 bg-pine-50"
          >
            <Image
              src={photo.src}
              alt={photo.alt}
              fill
              sizes="(max-width: 640px) 50vw, 33vw"
              className="object-cover transition-transform duration-500 group-hover:scale-105"
            />
          </figure>
        ))}
      </div>
    </div>
  );
}
