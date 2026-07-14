import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full font-medium transition-all duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-pine-600 focus-visible:ring-offset-2 focus-visible:ring-offset-cream disabled:pointer-events-none disabled:opacity-50 [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        primary:
          "bg-pine-700 text-cream shadow-soft hover:bg-pine-900 hover:shadow-lift hover:-translate-y-0.5",
        amber:
          "bg-amber text-cream-100 shadow-soft hover:bg-[#b3721f] hover:shadow-lift hover:-translate-y-0.5",
        outline:
          "border border-pine-700/30 text-pine-700 hover:border-pine-700 hover:bg-pine-700 hover:text-cream",
        ghost: "text-ink-soft hover:bg-pine-50 hover:text-pine-700",
        light:
          "bg-cream-100/90 text-pine-900 backdrop-blur hover:bg-cream-100 hover:-translate-y-0.5 shadow-soft",
      },
      size: {
        sm: "h-9 px-4 text-sm",
        md: "h-11 px-6 text-sm",
        lg: "h-14 px-8 text-base",
      },
    },
    defaultVariants: {
      variant: "primary",
      size: "md",
    },
  }
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, ...props }, ref) => (
    <button
      ref={ref}
      className={cn(buttonVariants({ variant, size, className }))}
      {...props}
    />
  )
);
Button.displayName = "Button";

export { Button, buttonVariants };
