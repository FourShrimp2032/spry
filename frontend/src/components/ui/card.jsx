import { cn } from "../../lib/utils";
export function Card({ className, ...props }) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-stone-200 bg-white shadow-sm",
        className,
      )}
      {...props}
    />
  );
}
