"""Django management command to backfill changesets, customized from the original one."""

from datetime import date, datetime, timedelta
from django.core.management.base import BaseCommand

from osmchadjango.changeset.models import Changeset
from osmchadjango.changeset.tasks import create_changeset

class Command(BaseCommand):
    help = """Backfill missing changesets by ID range or date range.
        Use --start_id for specific ID, --step=1/-1 for direction."""

    def add_arguments(self, parser):
        parser.add_argument("--start_date", type=str)
        parser.add_argument("--end_date", type=str)
        parser.add_argument("--start_id", type=int)
        parser.add_argument("--limit", type=int, default=50)
        parser.add_argument("--step", type=int, default=1)

    def handle(self, *args, **options):
        # Date defaults
        try:
            start_date = date.fromisoformat(options["start_date"])
        except:
            start_date = date.today() - timedelta(days=1)
        
        try:
            end_date = date.fromisoformat(options["end_date"])
        except:
            end_date = datetime.now().date()
        
        # Priority: ID mode > date mode
        if options["start_id"]:
            start_id = options["start_id"]
            # Get local context (recent IDs around start_id)
            cl = list(Changeset.objects.filter(id__gte=start_id - 100).values_list("id", flat=True))
            max_id = max(cl) if cl else start_id
            min_id = min(cl) if cl else start_id + options["step"]
            self.stdout.write(f"Backfilling from ID {start_id}, range {max_id} ↔ {min_id}")
            
            current_id = start_id
            count = 0
            while count < options["limit"]:
                if current_id not in cl:
                    try:
                        create_changeset(current_id)
                        self.stdout.write(f"✅ {current_id}")
                    except Exception as e:
                        self.stdout.write(f"✗ {current_id}: {e}")
                current_id += options["step"]
                count += 1
        else:
            # Original date-based logic + empty list FIX
            cl_qs = Changeset.objects.filter(date__gte=start_date, date__lte=end_date).values_list("id", flat=True)
            cl = list(cl_qs)
            
            if not cl:
                self.stdout.write("No changesets in date range. Use --start_id=25")
                return
            
            max_id = max(cl)
            min_id = min(cl)
            self.stdout.write(f"Found range: {min_id} ↔ {max_id}")
            
            current_id = max_id + 1
            count = 0
            while current_id < min_id and count < options["limit"]:
                try:
                    create_changeset(current_id)
                    self.stdout.write(f"✅ {current_id}")
                except Exception as e:
                    self.stdout.write(f"✗ {current_id}: {e}")
                current_id += 1
                count += 1

        self.stdout.write("✅ Complete")
        