"""
src/interface.py - Executive Workbook Generator (C_LEVEL_EXECUTIVE_SUITE Paradigm).
Builds C-Level formatted Excel artifacts for inetum_senior_data_scientist_bridge_project.
"""

import pandas as pd
from src.core_engine import create_engine

def export_executive_report(output_path="data/executive_report.xlsx"):
    engine = create_engine()
    df = engine.execute_analysis()
    
    with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
        df.to_excel(writer, sheet_name="Executive_Summary", index=False)
    print(f"[Executive Suite] Report exported successfully to: {output_path}")

if __name__ == "__main__":
    export_executive_report()