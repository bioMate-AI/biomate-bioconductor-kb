import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Compass } from "lucide-react";
import { Link } from "wouter";
import { t } from "@/lib/i18n";

export default function NotFound() {
  return (
    <div className="min-h-screen w-full flex items-center justify-center bg-gray-50">
      <Card className="w-full max-w-md mx-4">
        <CardContent className="pt-8 pb-6 flex flex-col items-center text-center">
          <Compass className="h-10 w-10 text-muted-foreground mb-4" />
          <h1 className="text-2xl font-bold text-gray-900">{t("not_found_page.title")}</h1>
          <p className="mt-3 text-sm text-gray-600">{t("not_found_page.body")}</p>
          <Button asChild className="mt-6">
            <Link href="/">{t("not_found_page.back")}</Link>
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
