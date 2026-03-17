"""
00_generate_sample_docs.py - Generate sample PDF documents for testing

Creates a set of sample IOC (Intelligent Operations Center) policy documents
as PDF files in data/documents/. These give the Knowledge Base something to
index and the agent something to answer questions about.

You can skip this script if you have your own PDFs - just place them in
data/documents/ and go straight to 01_upload_to_search.py.

Usage:
    python 00_generate_sample_docs.py
"""

import os
import sys
from pathlib import Path
from fpdf import FPDF

# Output directory
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DOCS_DIR = PROJECT_ROOT / "data" / "documents"


def create_pdf(filename: str, title: str, sections: list[tuple[str, str]]):
    """Create a simple PDF with a title page and multiple sections.

    Args:
        filename: Output filename (e.g. "safety_policy.pdf")
        title: Document title on the first page
        sections: List of (heading, body_text) tuples
    """
    pdf = FPDF()
    pdf.set_auto_page_break(auto=True, margin=15)

    # Title page
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 24)
    pdf.cell(0, 60, text="", new_x="LMARGIN", new_y="NEXT")  # spacer
    pdf.cell(0, 15, text=title, new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.set_font("Helvetica", "", 12)
    pdf.cell(0, 10, text="", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 10, text="Contoso IOC Health Check Program", new_x="LMARGIN", new_y="NEXT", align="C")
    pdf.cell(0, 8, text="Version 1.0 - 2025", new_x="LMARGIN", new_y="NEXT", align="C")

    # Content sections
    for heading, body in sections:
        pdf.add_page()
        pdf.set_font("Helvetica", "B", 16)
        pdf.cell(0, 12, text=heading, new_x="LMARGIN", new_y="NEXT")
        pdf.set_font("Helvetica", "", 11)
        pdf.ln(4)
        pdf.multi_cell(0, 6, text=body)

    output_path = DOCS_DIR / filename
    pdf.output(str(output_path))
    print(f"  [OK] {filename} ({len(sections)} sections)")


def main():
    DOCS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"\nGenerating sample PDF documents in {DOCS_DIR}\n")

    # ── Document 1: Equipment Health Policy ──────────────────────────────
    create_pdf(
        "equipment_health_policy.pdf",
        "Equipment Health Monitoring Policy",
        [
            ("1. Purpose and Scope", (
                "This policy defines the monitoring requirements for all critical equipment "
                "in Contoso's Intelligent Operations Center (IOC). It applies to all rotating "
                "machinery, heat exchangers, pressure vessels, and electrical systems across "
                "all operational facilities.\n\n"
                "The IOC health check program is designed to detect equipment anomalies early, "
                "reduce unplanned downtime, and extend asset life through predictive maintenance."
            )),
            ("2. Vibration Monitoring Thresholds", (
                "All rotating equipment must be monitored for vibration levels per ISO 10816 standards.\n\n"
                "Threshold levels:\n"
                "- Normal: 0 to 4.5 mm/s RMS velocity\n"
                "- Alert: 4.5 to 11.2 mm/s RMS velocity - investigate within 7 days\n"
                "- Alarm: 11.2 to 28.0 mm/s RMS velocity - schedule maintenance within 48 hours\n"
                "- Critical: Above 28.0 mm/s RMS velocity - immediate shutdown required\n\n"
                "Baseline readings must be taken within 30 days of installation or overhaul. "
                "Trending data must be reviewed weekly by the reliability engineering team."
            )),
            ("3. Temperature Monitoring", (
                "All heat exchangers, bearings, and electrical panels must have continuous "
                "temperature monitoring.\n\n"
                "Temperature thresholds:\n"
                "- Bearings: Alert at 80C, Alarm at 95C, Trip at 110C\n"
                "- Heat exchanger outlets: Alert at +10C above design, Alarm at +20C above design\n"
                "- Electrical panels: Alert at 60C, Alarm at 75C\n"
                "- Ambient temperature compensation must be applied for outdoor equipment\n\n"
                "Infrared thermography surveys must be conducted quarterly on all electrical "
                "distribution equipment rated above 480V."
            )),
            ("4. Pressure Monitoring", (
                "All pressure vessels and piping systems must comply with ASME and API standards.\n\n"
                "Pressure threshold guidelines:\n"
                "- Operating pressure must not exceed 90% of Maximum Allowable Working Pressure (MAWP)\n"
                "- Alert: 85% of MAWP\n"
                "- Alarm: 90% of MAWP\n"
                "- Relief valve set point: 100% of MAWP\n\n"
                "Pressure safety valves must be tested annually. All pressure readings must be "
                "logged at 1-minute intervals and retained for a minimum of 5 years."
            )),
            ("5. Corrosion Monitoring", (
                "Corrosion rates must be monitored using ultrasonic thickness (UT) measurements.\n\n"
                "Inspection frequency by corrosion rate:\n"
                "- Low (< 0.05 mm/year): UT every 5 years\n"
                "- Moderate (0.05 to 0.25 mm/year): UT every 2 years\n"
                "- High (0.25 to 0.50 mm/year): UT annually\n"
                "- Severe (> 0.50 mm/year): UT every 6 months, engineering assessment required\n\n"
                "Minimum wall thickness calculations must follow API 570 and API 510 as applicable. "
                "Any piping below retirement thickness must be replaced within 30 days."
            )),
        ],
    )

    # ── Document 2: Alarm Management Procedures ─────────────────────────
    create_pdf(
        "alarm_management_procedures.pdf",
        "Alarm Management Procedures",
        [
            ("1. Alarm Philosophy", (
                "The Contoso IOC alarm system follows ISA 18.2 / IEC 62682 standards for alarm management. "
                "The goal is to ensure that every alarm presented to an operator is relevant, "
                "unique, timely, prioritized, understandable, and actionable.\n\n"
                "Target alarm rates:\n"
                "- Steady state: Maximum 6 alarms per operator per hour (average over 24h)\n"
                "- Upset conditions: Maximum 10 alarms per operator per 10-minute period\n"
                "- Alarm flood: More than 10 alarms in 10 minutes - automatic suppression activated\n\n"
                "Standing alarms (active > 24 hours) must not exceed 5 at any time. "
                "All standing alarms must be reviewed weekly in the alarm rationalization meeting."
            )),
            ("2. Alarm Priority Matrix", (
                "Alarms are classified into four priority levels based on consequence severity "
                "and available response time:\n\n"
                "Priority 1 (Critical): Immediate safety or environmental risk. Response time: < 5 minutes.\n"
                "Priority 2 (High): Significant operational or financial impact. Response time: < 30 minutes.\n"
                "Priority 3 (Medium): Moderate operational impact. Response time: < 4 hours.\n"
                "Priority 4 (Low): Advisory / informational. Response time: next shift or planned maintenance.\n\n"
                "Priority distribution targets:\n"
                "- Critical: 1-5% of total configured alarms\n"
                "- High: 10-15%\n"
                "- Medium: 25-35%\n"
                "- Low: 45-55%\n\n"
                "Any alarm priority that does not meet these distribution targets must be reviewed "
                "in the quarterly alarm rationalization audit."
            )),
            ("3. Alarm Response Procedures", (
                "For every alarm, operators must follow the Acknowledge-Diagnose-Respond (ADR) cycle:\n\n"
                "Step 1 - Acknowledge: Operator acknowledges the alarm within the required response time.\n"
                "Step 2 - Diagnose: Identify the root cause using trend data, process graphics, and SOPs.\n"
                "Step 3 - Respond: Take corrective action per the Standard Operating Procedure (SOP) "
                "linked to the alarm.\n\n"
                "If the cause cannot be identified within the response window, escalate to the "
                "shift supervisor. If the alarm persists beyond 2x the response time, a formal "
                "incident report (IR) must be filed in the Contoso CMMS."
            )),
            ("4. Nuisance Alarm Management", (
                "A nuisance alarm is defined as one that activates more than 5 times in a 24-hour period "
                "without requiring operator action.\n\n"
                "Process for managing nuisance alarms:\n"
                "1. Operator logs the alarm in the nuisance alarm tracker\n"
                "2. Control systems engineer reviews within 7 days\n"
                "3. Options: adjust setpoint, add deadband, re-prioritize, or suppress with MOC\n"
                "4. Any suppressed alarm must have a reinstatement date (max 90 days)\n\n"
                "The overall nuisance alarm rate must not exceed 10% of total alarm activations. "
                "This metric is reviewed monthly by the alarm management team."
            )),
        ],
    )

    # ── Document 3: Safety and Environmental Guidelines ──────────────────
    create_pdf(
        "safety_environmental_guidelines.pdf",
        "Safety and Environmental Guidelines",
        [
            ("1. Process Safety Management", (
                "All IOC-monitored facilities must comply with OSHA PSM (29 CFR 1910.119) requirements.\n\n"
                "Key requirements:\n"
                "- Process Hazard Analysis (PHA) must be conducted every 5 years for each process unit\n"
                "- Management of Change (MOC) is required for any modification to process equipment, "
                "chemicals, technology, or operating procedures\n"
                "- Pre-Startup Safety Review (PSSR) required before commissioning any new or modified equipment\n"
                "- All Safety Instrumented Systems (SIS) must achieve SIL 2 or higher per IEC 61511\n\n"
                "IOC operators must complete annual PSM refresher training (minimum 8 hours). "
                "New operators must complete 40 hours of PSM training before independent operation."
            )),
            ("2. Environmental Monitoring", (
                "Continuous Emissions Monitoring Systems (CEMS) must be installed on all regulated sources.\n\n"
                "Emission limits:\n"
                "- SO2: Maximum 250 ppm (15-minute average)\n"
                "- NOx: Maximum 100 ppm (1-hour average)\n"
                "- CO: Maximum 200 ppm (1-hour average)\n"
                "- Particulate matter: Maximum 0.03 gr/dscf\n"
                "- VOCs: Maximum 20 ppm (as methane, 1-hour average)\n\n"
                "If any emission parameter exceeds 80% of the permit limit, the IOC must notify "
                "the environmental compliance team. Exceedances above permit limits must be reported "
                "to the regulatory agency within 24 hours."
            )),
            ("3. Water Discharge Limits", (
                "All facility water discharges must comply with NPDES permit requirements.\n\n"
                "Discharge limits for treated water:\n"
                "- pH: 6.0 to 9.0\n"
                "- Total Suspended Solids (TSS): Maximum 30 mg/L (daily), 15 mg/L (monthly average)\n"
                "- Oil and Grease: Maximum 10 mg/L (daily), 5 mg/L (monthly average)\n"
                "- BOD5: Maximum 30 mg/L (daily)\n"
                "- Temperature: Must not increase receiving water by more than 3C\n\n"
                "Daily discharge monitoring reports must be submitted to the IOC environmental dashboard. "
                "Any exceedance triggers automatic regulatory notification within 24 hours."
            )),
            ("4. Incident Response Requirements", (
                "The IOC is the central coordination point for all safety and environmental incidents.\n\n"
                "Response time requirements:\n"
                "- Fire/explosion: Activate Emergency Action Plan (EAP) within 2 minutes\n"
                "- Gas release: Activate shelter-in-place or evacuation within 3 minutes\n"
                "- Chemical spill: Notify hazmat team within 5 minutes, contain within 15 minutes\n"
                "- Environmental exceedance: Notify compliance team within 30 minutes\n\n"
                "Root Cause Analysis (RCA) required for:\n"
                "- Any recordable injury\n"
                "- Any environmental exceedance\n"
                "- Any unplanned shutdown lasting more than 4 hours\n"
                "- Any near-miss with potential for serious consequence\n\n"
                "RCA must be completed within 30 days and corrective actions tracked to closure in the CMMS."
            )),
        ],
    )

    print(f"\nDone! {len(list(DOCS_DIR.glob('*.pdf')))} PDFs created in {DOCS_DIR}")
    print(f"\nNext step:")
    print(f"  python 01_upload_to_search.py")


if __name__ == "__main__":
    main()
