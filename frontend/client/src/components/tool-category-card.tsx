import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { LucideIcon } from "lucide-react"
import { cn } from "@/lib/utils"

export interface ToolCategory {
  id: string;
  name: string;
  description: string;
  toolCount: number;
  icon: LucideIcon;
  color: string;
  tags: string[];
}

interface ToolCategoryCardProps {
  category: ToolCategory;
  onClick?: (category: ToolCategory) => void;
  className?: string;
}

export function ToolCategoryCard({ category, onClick, className }: ToolCategoryCardProps) {
  const Icon = category.icon;

  return (
    <Card
      className={cn(
        "cursor-pointer transition-all hover:shadow-md",
        className
      )}
      onClick={() => onClick?.(category)}
    >
      <CardHeader className="flex flex-row items-center gap-3 pb-2">
        <div className={cn("p-2 rounded-lg", category.color)}>
          <Icon className="h-5 w-5 text-white" />
        </div>
        <div>
          <CardTitle className="text-lg">{category.name}</CardTitle>
          <span className="text-sm text-muted-foreground">
            {category.toolCount} tools
          </span>
        </div>
      </CardHeader>
      <CardContent>
        <p className="text-sm text-muted-foreground mb-3">
          {category.description}
        </p>
        <div className="flex flex-wrap gap-1">
          {category.tags.map((tag) => (
            <Badge key={tag} variant="secondary" className="text-xs">
              {tag}
            </Badge>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
